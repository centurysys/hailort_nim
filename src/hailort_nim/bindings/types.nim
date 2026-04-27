import ./c_api

type
  # device
  DeviceId* = hailo_device_id_t
  PcieDeviceInfo* = hailo_pcie_device_info_t
  EthDeviceInfo* = hailo_eth_device_info_t
  DeviceType* = hailo_device_type_t
  DeviceIdentity* = hailo_device_identity_t
  CoreInformation* = hailo_core_information_t
  ExtendedDeviceInformation* = hailo_extended_device_information_t
  ChipTemperatureInfo* = hailo_chip_temperature_info_t
  ThrottlingLevel* = hailo_throttling_level_t
  HealthInfo* = hailo_health_info_t
  ResetDeviceMode* = hailo_reset_device_mode_t
  FwLoggerLevel* = hailo_fw_logger_level_t
  NotificationId* = hailo_notification_id_t

  # power measurement
  DvmOptions* = hailo_dvm_options_t
  PowerMeasurementType* = hailo_power_measurement_types_t
  AveragingFactor* = hailo_averaging_factor_t
  SamplingPeriod* = hailo_sampling_period_t
  MeasurementBufferIndex* = hailo_measurement_buffer_index_t
  PowerMeasurementData* = hailo_power_measurement_data_t

  # hef
  StreamInfo* = hailo_stream_info_t
  VStreamInfo* = hailo_vstream_info_t
  NetworkGroupInfo* = hailo_network_group_info_t
  LayerName* = hailo_layer_name_t
  NetworkInfo* = hailo_network_info_t

  # network group
  ConfigureNetworkGroupParams* = hailo_configure_network_group_params_t
  ActivateNetworkGroupParams* = hailo_activate_network_group_params_t
  OutputVstreamNameByGroup* = hailo_output_vstream_name_by_group_t
  LatencyMeasurementResult* = hailo_latency_measurement_result_t
  InputVstreamParamsByName* = hailo_input_vstream_params_by_name_t
  OutputVstreamParamsByName* = hailo_output_vstream_params_by_name_t

  # stream
  Format* = hailo_format_t
  QuantInfo* = hailo_quant_info_t
  TransformParams* = hailo_transform_params_t
  StreamDirection* = hailo_stream_direction_t
  StreamFlags* = hailo_stream_flags_t
  StreamParameters* = hailo_stream_parameters_t
  StreamParametersByName* = hailo_stream_parameters_by_name_t
  StreamWriteAsyncCompletionInfo* = hailo_stream_write_async_completion_info_t
  StreamReadAsyncCompletionInfo* = hailo_stream_read_async_completion_info_t
  StreamWriteAsyncCallback* = hailo_stream_write_async_callback_t
  StreamReadAsyncCallback* = hailo_stream_read_async_callback_t

  # vdevice
  VdeviceParams* = hailo_vdevice_params_t
  SchedulingAlgorithm* = hailo_scheduling_algorithm_t
  ConfigureParams* = hailo_configure_params_t
  ConfiguredNetworkGroup* = hailo_configured_network_group

  # vstream
  PixBuffer* = hailo_pix_buffer_t
