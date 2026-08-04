# AK80-9 V3.4 终端命令全表（真机 `help` 实测）

固件 `CMESC_AK80_9_SW_V3.4`，经 `kitcheck --terminal help` 读取，共 51 条。
通道：`COMM_TERMINAL_CMD`(20+65=0x55) 发，`COMM_PRINT`(21+65=0x56) 收，多帧。

```text
Valid commands are:
help
  Show this help
ping
  Print pong here to see if the reply works
stop
  Stop the motor
last_adc_duration
  The time the latest ADC interrupt consumed
kv
  The calculated kv of the motor
mem
  Show memory usage
threads
  List all threads
fault
  Prints the current fault code
faults
  Prints all stored fault codes and conditions when they arrived
rpm
  Prints the current electrical RPM
tacho
  Prints tachometer value
tim
  Prints tim1 and tim8 settings
volt
  Prints different voltages
param_detect [current] [min_rpm] [low_duty]
  Spin up the motor in COMM_MODE_DELAY and compute its parameters.
  This test should be performed without load on the motor.
  Example: param_detect 5.0 600 0.06
rpm_dep
  Prints some rpm-dep values
can_devs
  Prints all CAN devices seen on the bus the past second
foc_encoder_detect [current]
  Run the motor at 1Hz on open loop and compute encoder settings
measure_res [current]
  Lock the motor with a current and calculate its resistance
measure_ind [duty]
  Send short voltage pulses, measure the current and calculate the motor inductance
measure_linkage [current] [duty] [min_erpm] [motor_res]
  Run the motor in BLDC delay mode and measure the flux linkage
  example measure_linkage 5 0.5 700 0.076
  tip: measure the resistance with measure_res first
measure_res_ind
  Measure the motor resistance and inductance with an incremental adaptive algorithm.
measure_linkage_foc [duty]
  Run the motor with FOC and measure the flux linkage.
measure_linkage_openloop [current] [duty] [erpm_per_sec] [motor_res] [motor_ind]
  Run the motor in openloop FOC and measure the flux linkage
  example measure_linkage 5 0.5 1000 0.076 0.000015
  tip: measure the resistance with measure_res first
foc_state
  Print some FOC state variables.
hw_status
  Print some hardware status information.
foc_openloop [current] [erpm]
  Create an open loop rotating current vector.
foc_openloop_duty [duty] [erpm]
  Create an open loop rotating voltage vector.
nrf_ext_set_enabled [enabled]
  Enable or disable external NRF51822.
foc_sensors_detect_apply [current]
  Automatically detect FOC sensors, and apply settings on success.
rotor_lock_openloop [current_A] [time_S] [angle_DEG]
  Lock the motor with a current for a given time. Time 0 means forever, or
  or until the heartbeat packets stop.
foc_detect_apply_all [max_power_loss_W]
  Detect and apply all motor settings, based on maximum resistive motor power losses.
can_scan
  Scan CAN-bus using ping commands, and print all devices that are found.
foc_detect_apply_all_can [max_power_loss_W]
  Detect and apply all motor settings, based on maximum resistive motor power losses. Also
  initiates detection in all VESCs found on the CAN-bus.
encoder
  Prints the status of the AS5047, AD2S1205, or TS5700N8501 encoder.
encoder_clear_errors
  Clear error of the TS5700N8501 encoder.)
encoder_clear_multiturn
  Clear multiturn counter of the TS5700N8501 encoder.)
uptime
  Prints how many seconds have passed since boot.
hall_analyze [current]
  Rotate motor in open loop and analyze hall sensors.
Calibrate_outenc
  Calibrate the motor external encoder.
Accuracy_test
  Verify the results of calibrating the external encoder.
switche
  Switch display.
zhunquedu [error accuracy]
  Set error accuracy.
connect_virtual_motor [ml][J][Ld][Lq][Rs][lambda][Vbus]
  connects virtual motor
disconnect_virtual_motor
  disconnect virtual motor
foc_plot_hfi_en [en]
  Enable HFI plotting. 0: off, 1: DFT, 2: Raw
nunchuk_status
  Print the status of the nunchuk app
uavcan_debug [level]
  Enable UAVCAN debug prints (0 = off)
bm_swdp_scan
  BlackMagic: Scan SWD
bm_attach [index]
  BlackMagic: Attach target
bm_flash_erase [hex_addr] [len]
  BlackMagic: Erase flash memory
bm_target_help
  BlackMagic: Show target commands
bm_target_cmd [...]
  BlackMagic: Run command on target
bm_detach
  BlackMagic: Detach target
```
