import pandas as pd
import numpy as np
from ahrs.filters import Madgwick
from ahrs import Quaternion
from ahrs.common.orientation import acc2q
from scipy.signal import butter, filtfilt
import math
from scipy.spatial import cKDTree


def load_and_preprocess_imu(file_path):
    print("1. Завантаження даних IMU...")
    df = pd.read_csv(file_path)

    print("2. Фільтрація апаратних помилок та відкидання IMU 2 (Bosch)...")
    df = df[(df['GH'] == 1) & (df['AH'] == 1) &
            (df['EG'] == 0) & (df['EA'] == 0) &
            (df['I'].isin([0, 1]))]

    print("3. Злиття IMU 0 та IMU 1 (Virtual IMU)...")
    df_merged = df.groupby('TimeUS')[['GyrX', 'GyrY', 'GyrZ', 'AccX', 'AccY', 'AccZ']].mean().reset_index()

    start_time_us = df_merged['TimeUS'].min()

    t = (df_merged['TimeUS'] - start_time_us) / 1e6
    df_merged['TimeSec'] = t

    print("4. Калібрування (видалення статичного зсуву гіроскопа)...")
    stat_mask = df_merged['TimeSec'] <= 2.0
    gyr_bias = df_merged.loc[stat_mask, ['GyrX', 'GyrY', 'GyrZ']].mean().values
    df_merged[['GyrX', 'GyrY', 'GyrZ']] -= gyr_bias
    print(f"   Зсув гіроскопа компенсовано: {gyr_bias}")

    return df_merged, start_time_us


def process_barometer(file_path, start_time_us):
    print("-> Завантаження та обробка даних Барометра...")
    df = pd.read_csv(file_path)

    df = df[df['Health'] == 1]

    df['TimeSec'] = (df['TimeUS'] - start_time_us) / 1e6

    baro0 = df[df['I'] == 0].set_index('TimeSec')['Alt']
    baro1 = df[df['I'] == 1].set_index('TimeSec')['Alt']

    merged_alt = pd.concat([baro0, baro1], axis=1, keys=['Alt0', 'Alt1']).interpolate(method='index').bfill().ffill()

    merged_alt['Alt_Virtual'] = merged_alt['Alt0'] * 0.75 + merged_alt['Alt1'] * 0.25
    merged_alt = merged_alt.reset_index()

    print("-> Застосування LPF фільтра нульової фази до Барометра...")
    fs = 10.0
    cutoff = 1.0
    b, a = butter(2, cutoff / (0.5 * fs), btype='low')

    merged_alt['Alt_Smooth'] = filtfilt(b, a, merged_alt['Alt_Virtual'])

    base_alt = merged_alt.loc[merged_alt['TimeSec'] <= 2.0, 'Alt_Smooth'].mean()
    merged_alt['Alt_Smooth'] -= base_alt

    print("-> Розрахунок вертикальної швидкості (Vz)...")
    merged_alt['VelZ_Baro'] = np.gradient(merged_alt['Alt_Smooth'], merged_alt['TimeSec'])

    return merged_alt[['TimeSec', 'Alt_Smooth', 'VelZ_Baro']]


def calculate_trajectory(df_merged, baro_df, k_drag=0.5):
    print(f"5. Підготовка масивів для обчислення траєкторії (K_drag = {k_drag})...")
    t = df_merged['TimeSec'].values
    gyr = df_merged[['GyrX', 'GyrY', 'GyrZ']].values
    acc = df_merged[['AccX', 'AccY', 'AccZ']].values

    dt = np.diff(t)
    dt = np.insert(dt, 0, dt[0])

    print("6. Оцінка орієнтації (Фільтр Маджвіка)...")
    madgwick = Madgwick(gain=0.05)
    num_samples = len(t)
    Q = np.zeros((num_samples, 4))
    Q[0] = acc2q(acc[0])

    for i in range(1, num_samples):
        Q[i] = madgwick.updateIMU(Q[i - 1], gyr[i], acc[i], dt=dt[i])

    print("7. Переведення прискорень у глобальну систему координат...")
    acc_global = np.zeros_like(acc)
    for i in range(num_samples):
        q = Quaternion(Q[i])
        acc_global[i] = q.to_DCM() @ acc[i]

    static_acc = acc[t <= 2.0]
    g_norm = np.mean(np.linalg.norm(static_acc, axis=1))
    mean_z_global = np.mean(acc_global[t <= 2.0, 2])
    gravity_vector = np.array([0.0, 0.0, g_norm if mean_z_global > 0 else -g_norm])

    acc_linear = acc_global - gravity_vector

    print("8. Інтегрування X та Y (з аеродинамічним опором) + Барометр для Z...")
    vel = np.zeros_like(acc_linear)
    pos = np.zeros_like(acc_linear)

    interp_z = np.interp(t, baro_df['TimeSec'], baro_df['Alt_Smooth'])
    interp_vz = np.interp(t, baro_df['TimeSec'], baro_df['VelZ_Baro'])

    for i in range(1, num_samples):
        acc_x_effective = acc_linear[i, 0] - k_drag * vel[i - 1, 0]
        acc_y_effective = acc_linear[i, 1] - k_drag * vel[i - 1, 1]

        vel[i, 0] = vel[i - 1, 0] + acc_x_effective * dt[i]
        vel[i, 1] = vel[i - 1, 1] + acc_y_effective * dt[i]

        pos[i, 0] = pos[i - 1, 0] + vel[i - 1, 0] * dt[i] + 0.5 * acc_x_effective * dt[i] ** 2
        pos[i, 1] = pos[i - 1, 1] + vel[i - 1, 1] * dt[i] + 0.5 * acc_y_effective * dt[i] ** 2

    pos[:, 2] = interp_z
    vel[:, 2] = interp_vz

    result_df = pd.DataFrame({
        'timestamp': t,
        'x': pos[:, 0], 'y': pos[:, 1], 'z': pos[:, 2],
        'speed_x': vel[:, 0], 'speed_y': vel[:, 1], 'speed_z': vel[:, 2]
    })

    return result_df


def process_gps(file_path, start_time_us):
    print("-> Завантаження та обробка даних GPS...")
    df = pd.read_csv(file_path)

    df = df[df['Status'] >= 3].copy()

    df['TimeSec'] = (df['TimeUS'] - start_time_us) / 1e6

    lat0 = df['Lat'].iloc[0]
    lng0 = df['Lng'].iloc[0]
    alt0 = df['Alt'].iloc[0]

    R_earth = 6378137.0

    df['x'] = (df['Lng'] - lng0) * (math.pi / 180.0) * R_earth * math.cos(lat0 * math.pi / 180.0)
    df['y'] = (df['Lat'] - lat0) * (math.pi / 180.0) * R_earth
    df['z'] = df['Alt'] - alt0

    return df[['TimeSec', 'x', 'y', 'z']]


def calculate_errors(estimated_traj, gps_traj):
    print("\n--- Оцінка точності (Metrics) ---")

    est_points = estimated_traj[['x', 'y', 'z']].values
    gps_points = gps_traj[['x', 'y', 'z']].values

    est_final = est_points[-1]
    gps_final = gps_points[-1]

    endpoint_error = np.linalg.norm(est_final - gps_final)
    print(f"1. Endpoint Error: {endpoint_error:.2f} метрів")

    print("   Побудова просторового KD-дерева для еталонної траєкторії...")
    gps_tree = cKDTree(gps_points)

    distances, indices = gps_tree.query(est_points)

    rms_error = np.sqrt(np.mean(distances ** 2))

    print(f"2. RMS Crosstrack Error: {rms_error:.2f} метрів")

    max_error = np.max(distances)
    print(f"   Max Error (найбільше відхилення): {max_error:.2f} метрів")

    return {
        'Endpoint_Error': endpoint_error,
        'RMS_Error': rms_error,
        'Max_Error': max_error
    }


if __name__ == "__main__":
    imu_file_path = 'IMU.csv'
    baro_file_path = 'BARO.csv'
    gps_file_path = 'GPS.csv'

    clean_imu_data, start_time_us = load_and_preprocess_imu(imu_file_path)

    clean_baro_data = process_barometer(baro_file_path, start_time_us)

    trajectory = calculate_trajectory(clean_imu_data, clean_baro_data, k_drag=1)

    gps_trajectory = process_gps(gps_file_path, start_time_us)

    errors = calculate_errors(trajectory, gps_trajectory)

    trajectory.to_csv('Trajectory_Output.csv', index=False)

    print("\nПерші 5 точок траєкторії:")
    print(trajectory[['timestamp', 'x', 'y', 'z']].head())
    print("\nОстанні 5 точок траєкторії:")
    print(trajectory[['timestamp', 'x', 'y', 'z']].tail())