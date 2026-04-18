
type
  enum_hailo_status* {.size: sizeof(cuint).} = enum
    HAILO_SUCCESS = 0, HAILO_UNINITIALIZED = 1, HAILO_INVALID_ARGUMENT = 2,
    HAILO_OUT_OF_HOST_MEMORY = 3, HAILO_TIMEOUT = 4,
    HAILO_INSUFFICIENT_BUFFER = 5, HAILO_INVALID_OPERATION = 6,
    HAILO_NOT_IMPLEMENTED = 7, HAILO_INTERNAL_FAILURE = 8,
    HAILO_DATA_ALIGNMENT_FAILURE = 9, HAILO_CHUNK_TOO_LARGE = 10,
    HAILO_INVALID_LOGGER_LEVEL = 11, HAILO_CLOSE_FAILURE = 12,
    HAILO_OPEN_FILE_FAILURE = 13, HAILO_FILE_OPERATION_FAILURE = 14,
    HAILO_UNSUPPORTED_CONTROL_PROTOCOL_VERSION = 15,
    HAILO_UNSUPPORTED_FW_VERSION = 16, HAILO_INVALID_CONTROL_RESPONSE = 17,
    HAILO_FW_CONTROL_FAILURE = 18, HAILO_ETH_FAILURE = 19,
    HAILO_ETH_INTERFACE_NOT_FOUND = 20, HAILO_ETH_RECV_FAILURE = 21,
    HAILO_ETH_SEND_FAILURE = 22, HAILO_INVALID_FIRMWARE = 23,
    HAILO_INVALID_CONTEXT_COUNT = 24, HAILO_INVALID_FRAME = 25,
    HAILO_INVALID_HEF = 26, HAILO_PCIE_NOT_SUPPORTED_ON_PLATFORM = 27,
    HAILO_INTERRUPTED_BY_SIGNAL = 28, HAILO_START_VDMA_CHANNEL_FAIL = 29,
    HAILO_SYNC_VDMA_BUFFER_FAIL = 30, HAILO_STOP_VDMA_CHANNEL_FAIL = 31,
    HAILO_CLOSE_VDMA_CHANNEL_FAIL = 32,
    HAILO_ATR_TABLES_CONF_VALIDATION_FAIL = 33, HAILO_EVENT_CREATE_FAIL = 34,
    HAILO_READ_EVENT_FAIL = 35, HAILO_DRIVER_OPERATION_FAILED = 36,
    HAILO_INVALID_FIRMWARE_MAGIC = 37, HAILO_INVALID_FIRMWARE_CODE_SIZE = 38,
    HAILO_INVALID_KEY_CERTIFICATE_SIZE = 39,
    HAILO_INVALID_CONTENT_CERTIFICATE_SIZE = 40,
    HAILO_MISMATCHING_FIRMWARE_BUFFER_SIZES = 41,
    HAILO_INVALID_FIRMWARE_CPU_ID = 42,
    HAILO_CONTROL_RESPONSE_MD5_MISMATCH = 43,
    HAILO_GET_CONTROL_RESPONSE_FAIL = 44, HAILO_GET_D2H_EVENT_MESSAGE_FAIL = 45,
    HAILO_MUTEX_INIT_FAIL = 46, HAILO_OUT_OF_DESCRIPTORS = 47,
    HAILO_UNSUPPORTED_OPCODE = 48,
    HAILO_USER_MODE_RATE_LIMITER_NOT_SUPPORTED = 49,
    HAILO_RATE_LIMIT_MAXIMUM_BANDWIDTH_EXCEEDED = 50,
    HAILO_ANSI_TO_UTF16_CONVERSION_FAILED = 51,
    HAILO_UTF16_TO_ANSI_CONVERSION_FAILED = 52,
    HAILO_UNEXPECTED_INTERFACE_INFO_FAILURE = 53,
    HAILO_UNEXPECTED_ARP_TABLE_FAILURE = 54, HAILO_MAC_ADDRESS_NOT_FOUND = 55,
    HAILO_NO_IPV4_INTERFACES_FOUND = 56, HAILO_SHUTDOWN_EVENT_SIGNALED = 57,
    HAILO_THREAD_ALREADY_ACTIVATED = 58, HAILO_THREAD_NOT_ACTIVATED = 59,
    HAILO_THREAD_NOT_JOINABLE = 60, HAILO_NOT_FOUND = 61,
    HAILO_COMMUNICATION_CLOSED = 62, HAILO_STREAM_ABORT = 63,
    HAILO_DRIVER_NOT_INSTALLED = 64, HAILO_NOT_AVAILABLE = 65,
    HAILO_TRAFFIC_CONTROL_FAILURE = 66, HAILO_INVALID_SECOND_STAGE = 67,
    HAILO_INVALID_PIPELINE = 68, HAILO_NETWORK_GROUP_NOT_ACTIVATED = 69,
    HAILO_VSTREAM_PIPELINE_NOT_ACTIVATED = 70, HAILO_OUT_OF_FW_MEMORY = 71,
    HAILO_STREAM_NOT_ACTIVATED = 72, HAILO_DEVICE_IN_USE = 73,
    HAILO_OUT_OF_PHYSICAL_DEVICES = 74, HAILO_INVALID_DEVICE_ARCHITECTURE = 75,
    HAILO_INVALID_DRIVER_VERSION = 76, HAILO_RPC_FAILED = 77,
    HAILO_INVALID_SERVICE_VERSION = 78, HAILO_NOT_SUPPORTED = 79,
    HAILO_NMS_BURST_INVALID_DATA = 80, HAILO_OUT_OF_HOST_CMA_MEMORY = 81,
    HAILO_QUEUE_IS_FULL = 82, HAILO_DMA_MAPPING_ALREADY_EXISTS = 83,
    HAILO_CANT_MEET_BUFFER_REQUIREMENTS = 84,
    HAILO_DRIVER_INVALID_RESPONSE = 85, HAILO_DRIVER_INVALID_IOCTL = 86,
    HAILO_DRIVER_TIMEOUT = 87, HAILO_DRIVER_INTERRUPTED = 88,
    HAILO_CONNECTION_REFUSED = 89, HAILO_DRIVER_WAIT_CANCELED = 90,
    HAILO_HEF_FILE_CORRUPTED = 91, HAILO_HEF_NOT_SUPPORTED = 92,
    HAILO_HEF_NOT_COMPATIBLE_WITH_DEVICE = 93, HAILO_STATUS_COUNT = 94,
    HAILO_STATUS_MAX_ENUM = 2147483647
type
  enum_hailo_dvm_options_e* {.size: sizeof(cuint).} = enum
    HAILO_DVM_OPTIONS_VDD_CORE = 0, HAILO_DVM_OPTIONS_VDD_IO = 1,
    HAILO_DVM_OPTIONS_MIPI_AVDD = 2, HAILO_DVM_OPTIONS_MIPI_AVDD_H = 3,
    HAILO_DVM_OPTIONS_USB_AVDD_IO = 4, HAILO_DVM_OPTIONS_VDD_TOP = 5,
    HAILO_DVM_OPTIONS_USB_AVDD_IO_HV = 6, HAILO_DVM_OPTIONS_AVDD_H = 7,
    HAILO_DVM_OPTIONS_SDIO_VDD_IO = 8,
    HAILO_DVM_OPTIONS_OVERCURRENT_PROTECTION = 9, HAILO_DVM_OPTIONS_COUNT = 10,
    HAILO_DVM_OPTIONS_AUTO = 2147483647
const
  HAILO_DVM_OPTIONS_MAX_ENUM* = enum_hailo_dvm_options_e.HAILO_DVM_OPTIONS_AUTO
type
  enum_hailo_power_measurement_types_e* {.size: sizeof(cuint).} = enum
    HAILO_POWER_MEASUREMENT_TYPES_SHUNT_VOLTAGE = 0,
    HAILO_POWER_MEASUREMENT_TYPES_BUS_VOLTAGE = 1,
    HAILO_POWER_MEASUREMENT_TYPES_POWER = 2,
    HAILO_POWER_MEASUREMENT_TYPES_CURRENT = 3,
    HAILO_POWER_MEASUREMENT_TYPES_COUNT = 4,
    HAILO_POWER_MEASUREMENT_TYPES_AUTO = 2147483647
const
  HAILO_POWER_MEASUREMENT_TYPES_MAX_ENUM* = enum_hailo_power_measurement_types_e.HAILO_POWER_MEASUREMENT_TYPES_AUTO
type
  enum_hailo_sampling_period_e* {.size: sizeof(cuint).} = enum
    HAILO_SAMPLING_PERIOD_140US = 0, HAILO_SAMPLING_PERIOD_204US = 1,
    HAILO_SAMPLING_PERIOD_332US = 2, HAILO_SAMPLING_PERIOD_588US = 3,
    HAILO_SAMPLING_PERIOD_1100US = 4, HAILO_SAMPLING_PERIOD_2116US = 5,
    HAILO_SAMPLING_PERIOD_4156US = 6, HAILO_SAMPLING_PERIOD_8244US = 7,
    HAILO_SAMPLING_PERIOD_MAX_ENUM = 2147483647
type
  enum_hailo_averaging_factor_e* {.size: sizeof(cuint).} = enum
    HAILO_AVERAGE_FACTOR_1 = 0, HAILO_AVERAGE_FACTOR_4 = 1,
    HAILO_AVERAGE_FACTOR_16 = 2, HAILO_AVERAGE_FACTOR_64 = 3,
    HAILO_AVERAGE_FACTOR_128 = 4, HAILO_AVERAGE_FACTOR_256 = 5,
    HAILO_AVERAGE_FACTOR_512 = 6, HAILO_AVERAGE_FACTOR_1024 = 7,
    HAILO_AVERAGE_FACTOR_MAX_ENUM = 2147483647
type
  enum_hailo_measurement_buffer_index_e* {.size: sizeof(cuint).} = enum
    HAILO_MEASUREMENT_BUFFER_INDEX_0 = 0, HAILO_MEASUREMENT_BUFFER_INDEX_1 = 1,
    HAILO_MEASUREMENT_BUFFER_INDEX_2 = 2, HAILO_MEASUREMENT_BUFFER_INDEX_3 = 3,
    HAILO_MEASUREMENT_BUFFER_INDEX_MAX_ENUM = 2147483647
type
  enum_hailo_device_type_t* {.size: sizeof(cuint).} = enum
    HAILO_DEVICE_TYPE_PCIE = 0, HAILO_DEVICE_TYPE_ETH = 1,
    HAILO_DEVICE_TYPE_INTEGRATED = 2, HAILO_DEVICE_TYPE_MAX_ENUM = 2147483647
type
  enum_hailo_scheduling_algorithm_e* {.size: sizeof(cuint).} = enum
    HAILO_SCHEDULING_ALGORITHM_NONE = 0,
    HAILO_SCHEDULING_ALGORITHM_ROUND_ROBIN = 1,
    HAILO_SCHEDULING_ALGORITHM_MAX_ENUM = 2147483647
type
  enum_hailo_device_architecture_e* {.size: sizeof(cuint).} = enum
    HAILO_ARCH_HAILO8_A0 = 0, HAILO_ARCH_HAILO8 = 1, HAILO_ARCH_HAILO8L = 2,
    HAILO_ARCH_HAILO15H = 3, HAILO_ARCH_HAILO15L = 4, HAILO_ARCH_HAILO15M = 5,
    HAILO_ARCH_HAILO10H = 6, HAILO_ARCH_MARS = 7,
    HAILO_ARCH_MAX_ENUM = 2147483647
type
  enum_hailo_cpu_id_t* {.size: sizeof(cuint).} = enum
    HAILO_CPU_ID_0 = 0, HAILO_CPU_ID_1 = 1, HAILO_CPU_ID_MAX_ENUM = 2147483647
type
  enum_hailo_device_boot_source_t* {.size: sizeof(cuint).} = enum
    HAILO_DEVICE_BOOT_SOURCE_INVALID = 0, HAILO_DEVICE_BOOT_SOURCE_PCIE = 1,
    HAILO_DEVICE_BOOT_SOURCE_FLASH = 2,
    HAILO_DEVICE_BOOT_SOURCE_MAX = 2147483647
type
  enum_hailo_endianness_t* {.size: sizeof(cuint).} = enum
    HAILO_BIG_ENDIAN = 0, HAILO_LITTLE_ENDIAN = 1,
    HAILO_ENDIANNESS_MAX_ENUM = 2147483647
type
  enum_hailo_format_type_t* {.size: sizeof(cuint).} = enum
    HAILO_FORMAT_TYPE_AUTO = 0, HAILO_FORMAT_TYPE_UINT8 = 1,
    HAILO_FORMAT_TYPE_UINT16 = 2, HAILO_FORMAT_TYPE_FLOAT32 = 3,
    HAILO_FORMAT_TYPE_MAX_ENUM = 2147483647
type
  enum_hailo_format_order_t* {.size: sizeof(cuint).} = enum
    HAILO_FORMAT_ORDER_AUTO = 0, HAILO_FORMAT_ORDER_NHWC = 1,
    HAILO_FORMAT_ORDER_NHCW = 2, HAILO_FORMAT_ORDER_FCR = 3,
    HAILO_FORMAT_ORDER_F8CR = 4, HAILO_FORMAT_ORDER_NHW = 5,
    HAILO_FORMAT_ORDER_NC = 6, HAILO_FORMAT_ORDER_BAYER_RGB = 7,
    HAILO_FORMAT_ORDER_12_BIT_BAYER_RGB = 8, HAILO_FORMAT_ORDER_HAILO_NMS = 9,
    HAILO_FORMAT_ORDER_RGB888 = 10, HAILO_FORMAT_ORDER_NCHW = 11,
    HAILO_FORMAT_ORDER_YUY2 = 12, HAILO_FORMAT_ORDER_NV12 = 13,
    HAILO_FORMAT_ORDER_NV21 = 14, HAILO_FORMAT_ORDER_HAILO_YYUV = 15,
    HAILO_FORMAT_ORDER_HAILO_YYVU = 16, HAILO_FORMAT_ORDER_RGB4 = 17,
    HAILO_FORMAT_ORDER_I420 = 18, HAILO_FORMAT_ORDER_HAILO_YYYYUV = 19,
    HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK = 20,
    HAILO_FORMAT_ORDER_HAILO_NMS_ON_CHIP = 21,
    HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS = 22,
    HAILO_FORMAT_ORDER_HAILO_NMS_BY_SCORE = 23,
    HAILO_FORMAT_ORDER_MAX_ENUM = 2147483647
type
  enum_hailo_format_flags_t* {.size: sizeof(cuint).} = enum
    HAILO_FORMAT_FLAGS_NONE = 0, HAILO_FORMAT_FLAGS_QUANTIZED = 1,
    HAILO_FORMAT_FLAGS_TRANSPOSED = 2, HAILO_FORMAT_FLAGS_MAX_ENUM = 2147483647
type
  enum_hailo_stream_transform_mode_t* {.size: sizeof(cuint).} = enum
    HAILO_STREAM_NO_TRANSFORM = 0, HAILO_STREAM_TRANSFORM_COPY = 1,
    HAILO_STREAM_MAX_ENUM = 2147483647
type
  enum_hailo_stream_direction_t* {.size: sizeof(cuint).} = enum
    HAILO_H2D_STREAM = 0, HAILO_D2H_STREAM = 1,
    HAILO_STREAM_DIRECTION_MAX_ENUM = 2147483647
type
  enum_hailo_stream_flags_t* {.size: sizeof(cuint).} = enum
    HAILO_STREAM_FLAGS_NONE = 0, HAILO_STREAM_FLAGS_ASYNC = 1,
    HAILO_STREAM_FLAGS_MAX_ENUM = 2147483647
type
  enum_hailo_dma_buffer_direction_t* {.size: sizeof(cuint).} = enum
    HAILO_DMA_BUFFER_DIRECTION_H2D = 0, HAILO_DMA_BUFFER_DIRECTION_D2H = 1,
    HAILO_DMA_BUFFER_DIRECTION_BOTH = 2,
    HAILO_DMA_BUFFER_DIRECTION_MAX_ENUM = 2147483647
type
  enum_hailo_buffer_flags_t* {.size: sizeof(cuint).} = enum
    HAILO_BUFFER_FLAGS_NONE = 0, HAILO_BUFFER_FLAGS_DMA = 1,
    HAILO_BUFFER_FLAGS_CONTINUOUS = 2, HAILO_BUFFER_FLAGS_SHARED_MEMORY = 4,
    HAILO_BUFFER_FLAGS_MAX_ENUM = 2147483647
type
  enum_hailo_mipi_pixels_per_clock_t* {.size: sizeof(cuint).} = enum
    HAILO_MIPI_PIXELS_PER_CLOCK_1 = 0, HAILO_MIPI_PIXELS_PER_CLOCK_2 = 1,
    HAILO_MIPI_PIXELS_PER_CLOCK_4 = 2,
    HAILO_MIPI_PIXELS_PER_CLOCK_MAX_ENUM = 2147483647
type
  enum_hailo_mipi_clock_selection_t* {.size: sizeof(cuint).} = enum
    HAILO_MIPI_CLOCK_SELECTION_80_TO_100_MBPS = 0,
    HAILO_MIPI_CLOCK_SELECTION_100_TO_120_MBPS = 1,
    HAILO_MIPI_CLOCK_SELECTION_120_TO_160_MBPS = 2,
    HAILO_MIPI_CLOCK_SELECTION_160_TO_200_MBPS = 3,
    HAILO_MIPI_CLOCK_SELECTION_200_TO_240_MBPS = 4,
    HAILO_MIPI_CLOCK_SELECTION_240_TO_280_MBPS = 5,
    HAILO_MIPI_CLOCK_SELECTION_280_TO_320_MBPS = 6,
    HAILO_MIPI_CLOCK_SELECTION_320_TO_360_MBPS = 7,
    HAILO_MIPI_CLOCK_SELECTION_360_TO_400_MBPS = 8,
    HAILO_MIPI_CLOCK_SELECTION_400_TO_480_MBPS = 9,
    HAILO_MIPI_CLOCK_SELECTION_480_TO_560_MBPS = 10,
    HAILO_MIPI_CLOCK_SELECTION_560_TO_640_MBPS = 11,
    HAILO_MIPI_CLOCK_SELECTION_640_TO_720_MBPS = 12,
    HAILO_MIPI_CLOCK_SELECTION_720_TO_800_MBPS = 13,
    HAILO_MIPI_CLOCK_SELECTION_800_TO_880_MBPS = 14,
    HAILO_MIPI_CLOCK_SELECTION_880_TO_1040_MBPS = 15,
    HAILO_MIPI_CLOCK_SELECTION_1040_TO_1200_MBPS = 16,
    HAILO_MIPI_CLOCK_SELECTION_1200_TO_1350_MBPS = 17,
    HAILO_MIPI_CLOCK_SELECTION_1350_TO_1500_MBPS = 18,
    HAILO_MIPI_CLOCK_SELECTION_1500_TO_1750_MBPS = 19,
    HAILO_MIPI_CLOCK_SELECTION_1750_TO_2000_MBPS = 20,
    HAILO_MIPI_CLOCK_SELECTION_2000_TO_2250_MBPS = 21,
    HAILO_MIPI_CLOCK_SELECTION_2250_TO_2500_MBPS = 22,
    HAILO_MIPI_CLOCK_SELECTION_AUTOMATIC = 63,
    HAILO_MIPI_CLOCK_SELECTION_MAX_ENUM = 2147483647
type
  enum_hailo_mipi_data_type_rx_t* {.size: sizeof(cuint).} = enum
    HAILO_MIPI_RX_TYPE_RGB_444 = 32, HAILO_MIPI_RX_TYPE_RGB_555 = 33,
    HAILO_MIPI_RX_TYPE_RGB_565 = 34, HAILO_MIPI_RX_TYPE_RGB_666 = 35,
    HAILO_MIPI_RX_TYPE_RGB_888 = 36, HAILO_MIPI_RX_TYPE_RAW_6 = 40,
    HAILO_MIPI_RX_TYPE_RAW_7 = 41, HAILO_MIPI_RX_TYPE_RAW_8 = 42,
    HAILO_MIPI_RX_TYPE_RAW_10 = 43, HAILO_MIPI_RX_TYPE_RAW_12 = 44,
    HAILO_MIPI_RX_TYPE_RAW_14 = 45, HAILO_MIPI_RX_TYPE_MAX_ENUM = 2147483647
type
  enum_hailo_mipi_isp_image_in_order_t* {.size: sizeof(cuint).} = enum
    HAILO_MIPI_ISP_IMG_IN_ORDER_B_FIRST = 0,
    HAILO_MIPI_ISP_IMG_IN_ORDER_GB_FIRST = 1,
    HAILO_MIPI_ISP_IMG_IN_ORDER_GR_FIRST = 2,
    HAILO_MIPI_ISP_IMG_IN_ORDER_R_FIRST = 3,
    HAILO_MIPI_ISP_IMG_IN_ORDER_MAX_ENUM = 2147483647
type
  enum_hailo_mipi_isp_image_out_data_type_t* {.size: sizeof(cuint).} = enum
    HAILO_MIPI_IMG_OUT_DATA_TYPE_YUV_422 = 30,
    HAILO_MIPI_IMG_OUT_DATA_TYPE_RGB_888 = 36,
    HAILO_MIPI_IMG_OUT_DATA_TYPE_MAX_ENUM = 2147483647
type
  enum_hailo_mipi_isp_light_frequency_t* {.size: sizeof(cuint).} = enum
    HAILO_MIPI_ISP_LIGHT_FREQUENCY_60HZ = 0,
    HAILO_MIPI_ISP_LIGHT_FREQUENCY_50HZ = 1,
    ISP_LIGHT_FREQUENCY_MAX_ENUM = 2147483647
type
  enum_hailo_stream_interface_t* {.size: sizeof(cuint).} = enum
    HAILO_STREAM_INTERFACE_PCIE = 0, HAILO_STREAM_INTERFACE_ETH = 1,
    HAILO_STREAM_INTERFACE_MIPI = 2, HAILO_STREAM_INTERFACE_INTEGRATED = 3,
    HAILO_STREAM_INTERFACE_MAX_ENUM = 2147483647
type
  enum_hailo_vstream_stats_flags_t* {.size: sizeof(cuint).} = enum
    HAILO_VSTREAM_STATS_NONE = 0, HAILO_VSTREAM_STATS_MEASURE_FPS = 1,
    HAILO_VSTREAM_STATS_MEASURE_LATENCY = 2,
    HAILO_VSTREAM_STATS_MAX_ENUM = 2147483647
type
  enum_hailo_pipeline_elem_stats_flags_t* {.size: sizeof(cuint).} = enum
    HAILO_PIPELINE_ELEM_STATS_NONE = 0,
    HAILO_PIPELINE_ELEM_STATS_MEASURE_FPS = 1,
    HAILO_PIPELINE_ELEM_STATS_MEASURE_LATENCY = 2,
    HAILO_PIPELINE_ELEM_STATS_MEASURE_QUEUE_SIZE = 4,
    HAILO_PIPELINE_ELEM_STATS_MAX_ENUM = 2147483647
type
  enum_hailo_pix_buffer_memory_type_t* {.size: sizeof(cuint).} = enum
    HAILO_PIX_BUFFER_MEMORY_TYPE_USERPTR = 0,
    HAILO_PIX_BUFFER_MEMORY_TYPE_DMABUF = 1
type
  enum_hailo_nms_burst_type_t* {.size: sizeof(cuint).} = enum
    HAILO_BURST_TYPE_H8_BBOX = 0, HAILO_BURST_TYPE_H15_BBOX = 1,
    HAILO_BURST_TYPE_H8_PER_CLASS = 2, HAILO_BURST_TYPE_H15_PER_CLASS = 3,
    HAILO_BURST_TYPE_H15_PER_FRAME = 4, HAILO_BURST_TYPE_COUNT = 5
type
  enum_hailo_power_mode_t* {.size: sizeof(cuint).} = enum
    HAILO_POWER_MODE_PERFORMANCE = 0, HAILO_POWER_MODE_ULTRA_PERFORMANCE = 1,
    HAILO_POWER_MODE_MAX_ENUM = 2147483647
type
  enum_hailo_latency_measurement_flags_t* {.size: sizeof(cuint).} = enum
    HAILO_LATENCY_NONE = 0, HAILO_LATENCY_MEASURE = 1,
    HAILO_LATENCY_CLEAR_AFTER_GET = 2, HAILO_LATENCY_MAX_ENUM = 2147483647
type
  enum_hailo_notification_id_t* {.size: sizeof(cuint).} = enum
    HAILO_NOTIFICATION_ID_ETHERNET_RX_ERROR = 0,
    HAILO_NOTIFICATION_ID_HEALTH_MONITOR_TEMPERATURE_ALARM = 1,
    HAILO_NOTIFICATION_ID_HEALTH_MONITOR_DATAFLOW_SHUTDOWN = 2,
    HAILO_NOTIFICATION_ID_HEALTH_MONITOR_OVERCURRENT_ALARM = 3,
    HAILO_NOTIFICATION_ID_LCU_ECC_CORRECTABLE_ERROR = 4,
    HAILO_NOTIFICATION_ID_LCU_ECC_UNCORRECTABLE_ERROR = 5,
    HAILO_NOTIFICATION_ID_CPU_ECC_ERROR = 6,
    HAILO_NOTIFICATION_ID_CPU_ECC_FATAL = 7, HAILO_NOTIFICATION_ID_DEBUG = 8,
    HAILO_NOTIFICATION_ID_CONTEXT_SWITCH_BREAKPOINT_REACHED = 9,
    HAILO_NOTIFICATION_ID_HEALTH_MONITOR_CLOCK_CHANGED_EVENT = 10,
    HAILO_NOTIFICATION_ID_HW_INFER_MANAGER_INFER_DONE = 11,
    HAILO_NOTIFICATION_ID_CONTEXT_SWITCH_RUN_TIME_ERROR_EVENT = 12,
    HAILO_NOTIFICATION_ID_START_UPDATE_CACHE_OFFSET = 13,
    HAILO_NOTIFICATION_ID_COUNT = 14,
    HAILO_NOTIFICATION_ID_MAX_ENUM = 2147483647
type
  enum_hailo_temperature_protection_temperature_zone_t* {.size: sizeof(cuint).} = enum
    HAILO_TEMPERATURE_PROTECTION_TEMPERATURE_ZONE_GREEN = 0,
    HAILO_TEMPERATURE_PROTECTION_TEMPERATURE_ZONE_ORANGE = 1,
    HAILO_TEMPERATURE_PROTECTION_TEMPERATURE_ZONE_RED = 2
type
  enum_hailo_overcurrent_protection_overcurrent_zone_t* {.size: sizeof(cuint).} = enum
    HAILO_OVERCURRENT_PROTECTION_OVERCURRENT_ZONE_GREEN = 0,
    HAILO_OVERCURRENT_PROTECTION_OVERCURRENT_ZONE_RED = 1
type
  enum_hailo_reset_device_mode_t* {.size: sizeof(cuint).} = enum
    HAILO_RESET_DEVICE_MODE_CHIP = 0, HAILO_RESET_DEVICE_MODE_NN_CORE = 1,
    HAILO_RESET_DEVICE_MODE_SOFT = 2, HAILO_RESET_DEVICE_MODE_FORCED_SOFT = 3,
    HAILO_RESET_DEVICE_MODE_MAX_ENUM = 2147483647
type
  enum_hailo_watchdog_mode_t* {.size: sizeof(cuint).} = enum
    HAILO_WATCHDOG_MODE_HW_SW = 0, HAILO_WATCHDOG_MODE_HW_ONLY = 1,
    HAILO_WATCHDOG_MODE_MAX_ENUM = 2147483647
type
  enum_hailo_sensor_types_t* {.size: sizeof(cuint).} = enum
    HAILO_SENSOR_TYPES_HAILO8_ISP = -2147483648, HAILO_SENSOR_TYPES_GENERIC = 0,
    HAILO_SENSOR_TYPES_ONSEMI_AR0220AT = 1, HAILO_SENSOR_TYPES_RASPICAM = 2,
    HAILO_SENSOR_TYPES_ONSEMI_AS0149AT = 3,
    HAILO_SENSOR_TYPES_MAX_ENUM = 2147483647
type
  enum_hailo_fw_logger_interface_t* {.size: sizeof(cuint).} = enum
    HAILO_FW_LOGGER_INTERFACE_PCIE = 1, HAILO_FW_LOGGER_INTERFACE_UART = 2,
    HAILO_FW_LOGGER_INTERFACE_MAX_ENUM = 2147483647
type
  enum_hailo_fw_logger_level_t* {.size: sizeof(cuint).} = enum
    HAILO_FW_LOGGER_LEVEL_TRACE = 0, HAILO_FW_LOGGER_LEVEL_DEBUG = 1,
    HAILO_FW_LOGGER_LEVEL_INFO = 2, HAILO_FW_LOGGER_LEVEL_WARN = 3,
    HAILO_FW_LOGGER_LEVEL_ERROR = 4, HAILO_FW_LOGGER_LEVEL_FATAL = 5,
    HAILO_FW_LOGGER_LEVEL_MAX_ENUM = 2147483647
type
  enum_hailo_sleep_state_e* {.size: sizeof(cuint).} = enum
    HAILO_SLEEP_STATE_SLEEPING = 0, HAILO_SLEEP_STATE_AWAKE = 1,
    HAILO_SLEEP_STATE_MAX_ENUM = 2147483647
type
  struct_hailo_input_transform_context* = object
type
  struct_hailo_output_vstream* = object
type
  struct_hailo_output_transform_context* = object
type
  struct_hailo_hef* = object
type
  struct_hailo_vdevice* = object
type
  struct_hailo_scan_devices_params_t* = object
type
  compiler_INT_MAX_private* = object
type
  struct_hailo_output_demuxer* = object
type
  struct_hailo_activated_network_group* = object
type
  struct_hailo_output_stream* = object
type
  struct_hailo_configured_network_group* = object
type
  struct_hailo_device* = object
type
  struct_hailo_input_stream* = object
type
  struct_hailo_input_vstream* = object
type
  float32_t* = cfloat        ## Generated based on /usr/include/hailo/hailort.h:83:15
  float64_t* = cdouble       ## Generated based on /usr/include/hailo/hailort.h:84:16
  nms_bbox_counter_t* = uint16 ## Generated based on /usr/include/hailo/hailort.h:85:18
  hailo_status* = enum_hailo_status ## Generated based on /usr/include/hailo/hailort.h:194:3
  struct_hailo_version_t* {.pure, inheritable, bycopy.} = object
    major*: uint32           ## Generated based on /usr/include/hailo/hailort.h:201:9
    minor*: uint32
    revision*: uint32
  hailo_version_t* = struct_hailo_version_t ## Generated based on /usr/include/hailo/hailort.h:205:3
  hailo_device* = ptr struct_hailo_device ## Generated based on /usr/include/hailo/hailort.h:208:31
  hailo_vdevice* = ptr struct_hailo_vdevice ## Generated based on /usr/include/hailo/hailort.h:211:32
  hailo_hef* = ptr struct_hailo_hef ## Generated based on /usr/include/hailo/hailort.h:214:28
  hailo_input_stream* = ptr struct_hailo_input_stream ## Generated based on /usr/include/hailo/hailort.h:217:37
  hailo_output_stream* = ptr struct_hailo_output_stream ## Generated based on /usr/include/hailo/hailort.h:220:38
  hailo_configured_network_group* = ptr struct_hailo_configured_network_group ## Generated based on /usr/include/hailo/hailort.h:223:49
  hailo_activated_network_group* = ptr struct_hailo_activated_network_group ## Generated based on /usr/include/hailo/hailort.h:226:48
  hailo_input_transform_context* = ptr struct_hailo_input_transform_context ## Generated based on /usr/include/hailo/hailort.h:229:48
  hailo_output_transform_context* = ptr struct_hailo_output_transform_context ## Generated based on /usr/include/hailo/hailort.h:232:49
  hailo_output_demuxer* = ptr struct_hailo_output_demuxer ## Generated based on /usr/include/hailo/hailort.h:235:39
  hailo_input_vstream* = ptr struct_hailo_input_vstream ## Generated based on /usr/include/hailo/hailort.h:238:38
  hailo_output_vstream* = ptr struct_hailo_output_vstream ## Generated based on /usr/include/hailo/hailort.h:241:39
  hailo_dvm_options_t* = enum_hailo_dvm_options_e ## Generated based on /usr/include/hailo/hailort.h:283:3
  hailo_power_measurement_types_t* = enum_hailo_power_measurement_types_e ## Generated based on /usr/include/hailo/hailort.h:307:3
  hailo_sampling_period_t* = enum_hailo_sampling_period_e ## Generated based on /usr/include/hailo/hailort.h:322:3
  hailo_averaging_factor_t* = enum_hailo_averaging_factor_e ## Generated based on /usr/include/hailo/hailort.h:337:3
  hailo_measurement_buffer_index_t* = enum_hailo_measurement_buffer_index_e ## Generated based on /usr/include/hailo/hailort.h:348:3
  struct_hailo_power_measurement_data_t* {.pure, inheritable, bycopy.} = object
    average_value*: float32_t ## Generated based on /usr/include/hailo/hailort.h:351:9
    average_time_value_milliseconds*: float32_t
    min_value*: float32_t
    max_value*: float32_t
    total_number_of_samples*: uint32
  hailo_power_measurement_data_t* = struct_hailo_power_measurement_data_t ## Generated based on /usr/include/hailo/hailort.h:357:3
  hailo_scan_devices_params_t* = struct_hailo_scan_devices_params_t ## Generated based on /usr/include/hailo/hailort.h:360:45
  struct_hailo_eth_device_info_t* {.pure, inheritable, bycopy.} = object
    host_address*: struct_sockaddr_in ## Generated based on /usr/include/hailo/hailort.h:363:9
    device_address*: struct_sockaddr_in
    timeout_millis*: uint32
    max_number_of_attempts*: uint8
    max_payload_size*: uint16
  struct_sockaddr_in* {.pure, inheritable, bycopy.} = object
    sin_family*: sa_family_t ## Generated based on /usr/include/netinet/in.h:247:8
    sin_port*: in_port_t
    sin_addr*: struct_in_addr
    sin_zero*: array[8'i64, uint8]
  hailo_eth_device_info_t* = struct_hailo_eth_device_info_t ## Generated based on /usr/include/hailo/hailort.h:369:3
  struct_hailo_pcie_device_info_t* {.pure, inheritable, bycopy.} = object
    domain*: uint32          ## Generated based on /usr/include/hailo/hailort.h:372:9
    bus*: uint32
    device*: uint32
    func_field*: uint32
  hailo_pcie_device_info_t* = struct_hailo_pcie_device_info_t ## Generated based on /usr/include/hailo/hailort.h:377:3
  struct_hailo_device_id_t* {.pure, inheritable, bycopy.} = object
    id*: array[32'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:380:9
  hailo_device_id_t* = struct_hailo_device_id_t ## Generated based on /usr/include/hailo/hailort.h:382:3
  hailo_device_type_t* = enum_hailo_device_type_t ## Generated based on /usr/include/hailo/hailort.h:392:3
  hailo_scheduling_algorithm_t* = enum_hailo_scheduling_algorithm_e ## Generated based on /usr/include/hailo/hailort.h:403:3
  struct_hailo_vdevice_params_t* {.pure, inheritable, bycopy.} = object
    device_count*: uint32    ## Generated based on /usr/include/hailo/hailort.h:406:9
    device_ids*: ptr hailo_device_id_t
    scheduling_algorithm*: hailo_scheduling_algorithm_t
    group_id*: cstring
    multi_process_service*: bool
  hailo_vdevice_params_t* = struct_hailo_vdevice_params_t ## Generated based on /usr/include/hailo/hailort.h:425:3
  hailo_device_architecture_t* = enum_hailo_device_architecture_e ## Generated based on /usr/include/hailo/hailort.h:440:3
  hailo_cpu_id_t* = enum_hailo_cpu_id_t ## Generated based on /usr/include/hailo/hailort.h:448:3
  struct_hailo_firmware_version_t* {.pure, inheritable, bycopy.} = object
    major*: uint32           ## Generated based on /usr/include/hailo/hailort.h:451:9
    minor*: uint32
    revision*: uint32
  hailo_firmware_version_t* = struct_hailo_firmware_version_t ## Generated based on /usr/include/hailo/hailort.h:455:3
  struct_hailo_device_identity_t* {.pure, inheritable, bycopy.} = object
    protocol_version*: uint32 ## Generated based on /usr/include/hailo/hailort.h:458:9
    fw_version*: hailo_firmware_version_t
    logger_version*: uint32
    board_name_length*: uint8
    board_name*: array[32'i64, cschar]
    is_release*: bool
    extended_context_switch_buffer*: bool
    device_architecture*: hailo_device_architecture_t
    serial_number_length*: uint8
    serial_number*: array[16'i64, cschar]
    part_number_length*: uint8
    part_number*: array[16'i64, cschar]
    product_name_length*: uint8
    product_name*: array[42'i64, cschar]
  hailo_device_identity_t* = struct_hailo_device_identity_t ## Generated based on /usr/include/hailo/hailort.h:473:3
  struct_hailo_core_information_t* {.pure, inheritable, bycopy.} = object
    is_release*: bool        ## Generated based on /usr/include/hailo/hailort.h:475:9
    extended_context_switch_buffer*: bool
    fw_version*: hailo_firmware_version_t
  hailo_core_information_t* = struct_hailo_core_information_t ## Generated based on /usr/include/hailo/hailort.h:479:3
  hailo_device_boot_source_t* = enum_hailo_device_boot_source_t ## Generated based on /usr/include/hailo/hailort.h:489:3
  struct_hailo_device_supported_features_t* {.pure, inheritable, bycopy.} = object
    ethernet*: bool          ## Generated based on /usr/include/hailo/hailort.h:492:9
    mipi*: bool
    pcie*: bool
    current_monitoring*: bool
    mdio*: bool
  hailo_device_supported_features_t* = struct_hailo_device_supported_features_t ## Generated based on /usr/include/hailo/hailort.h:503:3
  struct_hailo_extended_device_information_t* {.pure, inheritable, bycopy.} = object
    neural_network_core_clock_rate*: uint32 ## Generated based on /usr/include/hailo/hailort.h:506:9
    supported_features*: hailo_device_supported_features_t
    boot_source*: hailo_device_boot_source_t
    soc_id*: array[32'i64, uint8]
    lcs*: uint8
    eth_mac_address*: array[6'i64, uint8]
    unit_level_tracking_id*: array[12'i64, uint8]
    soc_pm_values*: array[24'i64, uint8]
    gpio_mask*: uint16
  hailo_extended_device_information_t* = struct_hailo_extended_device_information_t ## Generated based on /usr/include/hailo/hailort.h:525:3
  hailo_endianness_t* = enum_hailo_endianness_t ## Generated based on /usr/include/hailo/hailort.h:534:3
  struct_hailo_i2c_slave_config_t* {.pure, inheritable, bycopy.} = object
    endianness*: hailo_endianness_t ## Generated based on /usr/include/hailo/hailort.h:537:9
    slave_address*: uint16
    register_address_size*: uint8
    bus_index*: uint8
    should_hold_bus*: bool
  hailo_i2c_slave_config_t* = struct_hailo_i2c_slave_config_t ## Generated based on /usr/include/hailo/hailort.h:543:3
  struct_hailo_fw_user_config_information_t* {.pure, inheritable, bycopy.} = object
    version*: uint32         ## Generated based on /usr/include/hailo/hailort.h:546:9
    entry_count*: uint32
    total_size*: uint32
  hailo_fw_user_config_information_t* = struct_hailo_fw_user_config_information_t ## Generated based on /usr/include/hailo/hailort.h:550:3
  hailo_format_type_t* = enum_hailo_format_type_t ## Generated based on /usr/include/hailo/hailort.h:571:3
  hailo_format_order_t* = enum_hailo_format_order_t ## Generated based on /usr/include/hailo/hailort.h:792:3
  hailo_format_flags_t* = enum_hailo_format_flags_t ## Generated based on /usr/include/hailo/hailort.h:825:3
  struct_hailo_format_t* {.pure, inheritable, bycopy.} = object
    type_field*: hailo_format_type_t ## Generated based on /usr/include/hailo/hailort.h:828:9
    order*: hailo_format_order_t
    flags*: hailo_format_flags_t
  hailo_format_t* = struct_hailo_format_t ## Generated based on /usr/include/hailo/hailort.h:832:3
  hailo_stream_transform_mode_t* = enum_hailo_stream_transform_mode_t ## Generated based on /usr/include/hailo/hailort.h:844:3
  hailo_stream_direction_t* = enum_hailo_stream_direction_t ## Generated based on /usr/include/hailo/hailort.h:853:3
  hailo_stream_flags_t* = enum_hailo_stream_flags_t ## Generated based on /usr/include/hailo/hailort.h:862:3
  hailo_dma_buffer_direction_t* = enum_hailo_dma_buffer_direction_t ## Generated based on /usr/include/hailo/hailort.h:877:3
  hailo_buffer_flags_t* = enum_hailo_buffer_flags_t ## Generated based on /usr/include/hailo/hailort.h:891:3
  struct_hailo_buffer_parameters_t* {.pure, inheritable, bycopy.} = object
    flags*: hailo_buffer_flags_t ## Generated based on /usr/include/hailo/hailort.h:894:9
  hailo_buffer_parameters_t* = struct_hailo_buffer_parameters_t ## Generated based on /usr/include/hailo/hailort.h:896:3
  struct_hailo_transform_params_t* {.pure, inheritable, bycopy.} = object
    transform_mode*: hailo_stream_transform_mode_t ## Generated based on /usr/include/hailo/hailort.h:902:9
    user_buffer_format*: hailo_format_t
  hailo_transform_params_t* = struct_hailo_transform_params_t ## Generated based on /usr/include/hailo/hailort.h:905:3
  struct_hailo_demux_params_t* {.pure, inheritable, bycopy.} = object
    reserved*: uint8         ## Generated based on /usr/include/hailo/hailort.h:908:9
  hailo_demux_params_t* = struct_hailo_demux_params_t ## Generated based on /usr/include/hailo/hailort.h:910:3
  struct_hailo_quant_info_t* {.pure, inheritable, bycopy.} = object
    qp_zp*: float32_t        ## Generated based on /usr/include/hailo/hailort.h:921:9
    qp_scale*: float32_t
    limvals_min*: float32_t
    limvals_max*: float32_t
  hailo_quant_info_t* = struct_hailo_quant_info_t ## Generated based on /usr/include/hailo/hailort.h:933:3
  struct_hailo_eth_input_stream_params_t* {.pure, inheritable, bycopy.} = object
    host_address*: struct_sockaddr_in ## Generated based on /usr/include/hailo/hailort.h:936:9
    device_port*: port_t
    is_sync_enabled*: bool
    frames_per_sync*: uint32
    max_payload_size*: uint16
    rate_limit_bytes_per_sec*: uint32
    buffers_threshold*: uint32
  port_t* = in_port_t        ## Generated based on /usr/include/hailo/platform.h:68:19
  hailo_eth_input_stream_params_t* = struct_hailo_eth_input_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:958:3
  struct_hailo_eth_output_stream_params_t* {.pure, inheritable, bycopy.} = object
    host_address*: struct_sockaddr_in ## Generated based on /usr/include/hailo/hailort.h:961:9
    device_port*: port_t
    is_sync_enabled*: bool
    max_payload_size*: uint16
    buffers_threshold*: uint32
  hailo_eth_output_stream_params_t* = struct_hailo_eth_output_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:967:3
  struct_hailo_pcie_input_stream_params_t* {.pure, inheritable, bycopy.} = object
    reserved*: uint8         ## Generated based on /usr/include/hailo/hailort.h:970:9
  hailo_pcie_input_stream_params_t* = struct_hailo_pcie_input_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:972:3
  struct_hailo_pcie_output_stream_params_t* {.pure, inheritable, bycopy.} = object
    reserved*: uint8         ## Generated based on /usr/include/hailo/hailort.h:975:9
  hailo_pcie_output_stream_params_t* = struct_hailo_pcie_output_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:977:3
  hailo_mipi_pixels_per_clock_t* = enum_hailo_mipi_pixels_per_clock_t ## Generated based on /usr/include/hailo/hailort.h:987:3
  hailo_mipi_clock_selection_t* = enum_hailo_mipi_clock_selection_t ## Generated based on /usr/include/hailo/hailort.h:1020:3
  hailo_mipi_data_type_rx_t* = enum_hailo_mipi_data_type_rx_t ## Generated based on /usr/include/hailo/hailort.h:1038:3
  hailo_mipi_isp_image_in_order_t* = enum_hailo_mipi_isp_image_in_order_t ## Generated based on /usr/include/hailo/hailort.h:1049:3
  hailo_mipi_isp_image_out_data_type_t* = enum_hailo_mipi_isp_image_out_data_type_t ## Generated based on /usr/include/hailo/hailort.h:1058:3
  hailo_mipi_isp_light_frequency_t* = enum_hailo_mipi_isp_light_frequency_t ## Generated based on /usr/include/hailo/hailort.h:1066:3
  struct_hailo_mipi_common_params_t* {.pure, inheritable, bycopy.} = object
    img_width_pixels*: uint16 ## Generated based on /usr/include/hailo/hailort.h:1069:9
    img_height_pixels*: uint16
    pixels_per_clock*: hailo_mipi_pixels_per_clock_t
    number_of_lanes*: uint8
    clock_selection*: hailo_mipi_clock_selection_t
    virtual_channel_index*: uint8
    data_rate*: uint32
  hailo_mipi_common_params_t* = struct_hailo_mipi_common_params_t ## Generated based on /usr/include/hailo/hailort.h:1094:3
  struct_hailo_isp_params_t* {.pure, inheritable, bycopy.} = object
    isp_img_in_order*: hailo_mipi_isp_image_in_order_t ## Generated based on /usr/include/hailo/hailort.h:1097:9
    isp_img_out_data_type*: hailo_mipi_isp_image_out_data_type_t
    isp_crop_enable*: bool
    isp_crop_output_width_pixels*: uint16
    isp_crop_output_height_pixels*: uint16
    isp_crop_output_width_start_offset_pixels*: uint16
    isp_crop_output_height_start_offset_pixels*: uint16
    isp_test_pattern_enable*: bool
    isp_configuration_bypass*: bool
    isp_run_time_ae_enable*: bool
    isp_run_time_awb_enable*: bool
    isp_run_time_adt_enable*: bool
    isp_run_time_af_enable*: bool
    isp_run_time_calculations_interval_ms*: uint16
    isp_light_frequency*: hailo_mipi_isp_light_frequency_t
  hailo_isp_params_t* = struct_hailo_isp_params_t ## Generated based on /usr/include/hailo/hailort.h:1147:3
  struct_hailo_mipi_input_stream_params_t* {.pure, inheritable, bycopy.} = object
    mipi_common_params*: hailo_mipi_common_params_t ## Generated based on /usr/include/hailo/hailort.h:1150:9
    mipi_rx_id*: uint8
    data_type*: hailo_mipi_data_type_rx_t
    isp_enable*: bool
    isp_params*: hailo_isp_params_t
  hailo_mipi_input_stream_params_t* = struct_hailo_mipi_input_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:1163:3
  struct_hailo_integrated_input_stream_params_t* {.pure, inheritable, bycopy.} = object
    reserved*: uint8         ## Generated based on /usr/include/hailo/hailort.h:1166:9
  hailo_integrated_input_stream_params_t* = struct_hailo_integrated_input_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:1168:3
  struct_hailo_integrated_output_stream_params_t* {.pure, inheritable, bycopy.} = object
    reserved*: uint8         ## Generated based on /usr/include/hailo/hailort.h:1171:9
  hailo_integrated_output_stream_params_t* = struct_hailo_integrated_output_stream_params_t ## Generated based on /usr/include/hailo/hailort.h:1173:3
  hailo_stream_interface_t* = enum_hailo_stream_interface_t ## Generated based on /usr/include/hailo/hailort.h:1183:3
  struct_hailo_stream_parameters_t_anon0_t* {.union, bycopy.} = object
    pcie_input_params*: hailo_pcie_input_stream_params_t
    integrated_input_params*: hailo_integrated_input_stream_params_t
    eth_input_params*: hailo_eth_input_stream_params_t
    mipi_input_params*: hailo_mipi_input_stream_params_t
    pcie_output_params*: hailo_pcie_output_stream_params_t
    integrated_output_params*: hailo_integrated_output_stream_params_t
    eth_output_params*: hailo_eth_output_stream_params_t
  struct_hailo_stream_parameters_t* {.pure, inheritable, bycopy.} = object
    stream_interface*: hailo_stream_interface_t ## Generated based on /usr/include/hailo/hailort.h:1186:9
    direction*: hailo_stream_direction_t
    flags*: hailo_stream_flags_t
    anon0*: struct_hailo_stream_parameters_t_anon0_t
  hailo_stream_parameters_t* = struct_hailo_stream_parameters_t ## Generated based on /usr/include/hailo/hailort.h:1199:3
  struct_hailo_stream_parameters_by_name_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1202:9
    stream_params*: hailo_stream_parameters_t
  hailo_stream_parameters_by_name_t* = struct_hailo_stream_parameters_by_name_t ## Generated based on /usr/include/hailo/hailort.h:1205:3
  hailo_vstream_stats_flags_t* = enum_hailo_vstream_stats_flags_t ## Generated based on /usr/include/hailo/hailort.h:1215:3
  hailo_pipeline_elem_stats_flags_t* = enum_hailo_pipeline_elem_stats_flags_t ## Generated based on /usr/include/hailo/hailort.h:1226:3
  struct_hailo_vstream_params_t* {.pure, inheritable, bycopy.} = object
    user_buffer_format*: hailo_format_t ## Generated based on /usr/include/hailo/hailort.h:1229:9
    timeout_ms*: uint32
    queue_size*: uint32
    vstream_stats_flags*: hailo_vstream_stats_flags_t
    pipeline_elements_stats_flags*: hailo_pipeline_elem_stats_flags_t
  hailo_vstream_params_t* = struct_hailo_vstream_params_t ## Generated based on /usr/include/hailo/hailort.h:1235:3
  struct_hailo_input_vstream_params_by_name_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1238:9
    params*: hailo_vstream_params_t
  hailo_input_vstream_params_by_name_t* = struct_hailo_input_vstream_params_by_name_t ## Generated based on /usr/include/hailo/hailort.h:1241:3
  struct_hailo_output_vstream_params_by_name_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1244:9
    params*: hailo_vstream_params_t
  hailo_output_vstream_params_by_name_t* = struct_hailo_output_vstream_params_by_name_t ## Generated based on /usr/include/hailo/hailort.h:1247:3
  struct_hailo_output_vstream_name_by_group_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1250:9
    pipeline_group_index*: uint8
  hailo_output_vstream_name_by_group_t* = struct_hailo_output_vstream_name_by_group_t ## Generated based on /usr/include/hailo/hailort.h:1253:3
  struct_hailo_3d_image_shape_t* {.pure, inheritable, bycopy.} = object
    height*: uint32          ## Generated based on /usr/include/hailo/hailort.h:1256:9
    width*: uint32
    features*: uint32
  hailo_3d_image_shape_t* = struct_hailo_3d_image_shape_t ## Generated based on /usr/include/hailo/hailort.h:1260:3
  hailo_pix_buffer_memory_type_t* = enum_hailo_pix_buffer_memory_type_t ## Generated based on /usr/include/hailo/hailort.h:1266:3
  struct_hailo_pix_buffer_plane_t_anon0_t* {.union, bycopy.} = object
    user_ptr*: pointer
    fd*: cint
  struct_hailo_pix_buffer_plane_t* {.pure, inheritable, bycopy.} = object
    bytes_used*: uint32      ## Generated based on /usr/include/hailo/hailort.h:1269:9
    plane_size*: uint32
    anon0*: struct_hailo_pix_buffer_plane_t_anon0_t
  hailo_pix_buffer_plane_t* = struct_hailo_pix_buffer_plane_t ## Generated based on /usr/include/hailo/hailort.h:1279:3
  struct_hailo_pix_buffer_t* {.pure, inheritable, bycopy.} = object
    index*: uint32           ## Generated based on /usr/include/hailo/hailort.h:1282:9
    planes*: array[4'i64, hailo_pix_buffer_plane_t]
    number_of_planes*: uint32
    memory_type*: hailo_pix_buffer_memory_type_t
  hailo_pix_buffer_t* = struct_hailo_pix_buffer_t ## Generated based on /usr/include/hailo/hailort.h:1287:3
  struct_hailo_dma_buffer_t* {.pure, inheritable, bycopy.} = object
    fd*: cint                ## Generated based on /usr/include/hailo/hailort.h:1290:9
    size*: csize_t
  hailo_dma_buffer_t* = struct_hailo_dma_buffer_t ## Generated based on /usr/include/hailo/hailort.h:1293:3
  struct_hailo_nms_defuse_info_t* {.pure, inheritable, bycopy.} = object
    class_group_index*: uint32 ## Generated based on /usr/include/hailo/hailort.h:1295:9
    original_name*: array[128'i64, cschar]
  hailo_nms_defuse_info_t* = struct_hailo_nms_defuse_info_t ## Generated based on /usr/include/hailo/hailort.h:1298:3
  hailo_nms_burst_type_t* = enum_hailo_nms_burst_type_t ## Generated based on /usr/include/hailo/hailort.h:1308:3
  struct_hailo_nms_info_t* {.pure, inheritable, bycopy.} = object
    number_of_classes*: uint32 ## Generated based on /usr/include/hailo/hailort.h:1311:9
    max_bboxes_per_class*: uint32
    max_bboxes_total*: uint32
    bbox_size*: uint32
    chunks_per_frame*: uint32
    is_defused*: bool
    defuse_info*: hailo_nms_defuse_info_t
    burst_size*: uint32
    burst_type*: hailo_nms_burst_type_t
  hailo_nms_info_t* = struct_hailo_nms_info_t ## Generated based on /usr/include/hailo/hailort.h:1328:3
  struct_hailo_nms_fuse_input_t* {.pure, inheritable, bycopy.} = object
    buffer*: pointer         ## Generated based on /usr/include/hailo/hailort.h:1331:9
    size*: csize_t
    nms_info*: hailo_nms_info_t
  hailo_nms_fuse_input_t* = struct_hailo_nms_fuse_input_t ## Generated based on /usr/include/hailo/hailort.h:1335:3
  struct_hailo_nms_shape_t* {.pure, inheritable, bycopy.} = object
    number_of_classes*: uint32 ## Generated based on /usr/include/hailo/hailort.h:1338:9
    max_bboxes_per_class*: uint32
    max_bboxes_total*: uint32
    max_accumulated_mask_size*: uint32
  hailo_nms_shape_t* = struct_hailo_nms_shape_t ## Generated based on /usr/include/hailo/hailort.h:1350:3
  struct_hailo_bbox_t* {.pure, inheritable, bycopy.} = object
    y_min*: uint16           ## Generated based on /usr/include/hailo/hailort.h:1353:9
    x_min*: uint16
    y_max*: uint16
    x_max*: uint16
    score*: uint16
  hailo_bbox_t* = struct_hailo_bbox_t ## Generated based on /usr/include/hailo/hailort.h:1359:3
  struct_hailo_bbox_float32_t* {.pure, inheritable, bycopy.} = object
    y_min*: float32_t        ## Generated based on /usr/include/hailo/hailort.h:1361:9
    x_min*: float32_t
    y_max*: float32_t
    x_max*: float32_t
    score*: float32_t
  hailo_bbox_float32_t* = struct_hailo_bbox_float32_t ## Generated based on /usr/include/hailo/hailort.h:1367:3
  struct_hailo_rectangle_t* {.pure, inheritable, bycopy.} = object
    y_min*: float32_t        ## Generated based on /usr/include/hailo/hailort.h:1369:9
    x_min*: float32_t
    y_max*: float32_t
    x_max*: float32_t
  hailo_rectangle_t* = struct_hailo_rectangle_t ## Generated based on /usr/include/hailo/hailort.h:1374:3
  struct_hailo_detection_t* {.pure, inheritable, bycopy.} = object
    y_min*: float32_t        ## Generated based on /usr/include/hailo/hailort.h:1376:9
    x_min*: float32_t
    y_max*: float32_t
    x_max*: float32_t
    score*: float32_t
    class_id*: uint16
  hailo_detection_t* = struct_hailo_detection_t ## Generated based on /usr/include/hailo/hailort.h:1383:3
  struct_hailo_detections_t* {.pure, inheritable, bycopy.} = object
    count*: uint16           ## Generated based on /usr/include/hailo/hailort.h:1390:9
    detections*: array[0'i64, hailo_detection_t]
  hailo_detections_t* = struct_hailo_detections_t ## Generated based on /usr/include/hailo/hailort.h:1396:3
  struct_hailo_detection_with_byte_mask_t* {.pure, inheritable, bycopy.} = object
    box*: hailo_rectangle_t  ## Generated based on /usr/include/hailo/hailort.h:1401:9
    score*: float32_t
    class_id*: uint16
    mask_size*: csize_t
    mask*: ptr uint8
  hailo_detection_with_byte_mask_t* = struct_hailo_detection_with_byte_mask_t ## Generated based on /usr/include/hailo/hailort.h:1426:3
  struct_hailo_stream_write_async_completion_info_t* {.pure, inheritable, bycopy.} = object
    status*: hailo_status    ## Generated based on /usr/include/hailo/hailort.h:1433:9
    buffer_addr*: pointer
    buffer_size*: csize_t
    opaque*: pointer
  hailo_stream_write_async_completion_info_t* = struct_hailo_stream_write_async_completion_info_t ## Generated based on /usr/include/hailo/hailort.h:1450:3
  hailo_stream_write_async_callback_t* = proc (
      a0: ptr hailo_stream_write_async_completion_info_t): void {.cdecl.} ## Generated based on /usr/include/hailo/hailort.h:1455:16
  struct_hailo_stream_read_async_completion_info_t* {.pure, inheritable, bycopy.} = object
    status*: hailo_status    ## Generated based on /usr/include/hailo/hailort.h:1461:9
    buffer_addr*: pointer
    buffer_size*: csize_t
    opaque*: pointer
  hailo_stream_read_async_completion_info_t* = struct_hailo_stream_read_async_completion_info_t ## Generated based on /usr/include/hailo/hailort.h:1478:3
  hailo_stream_read_async_callback_t* = proc (
      a0: ptr hailo_stream_read_async_completion_info_t): void {.cdecl.} ## Generated based on /usr/include/hailo/hailort.h:1483:16
  struct_hailo_stream_info_t_anon0_t_anon0_t* {.pure, inheritable, bycopy.} = object
    shape*: hailo_3d_image_shape_t
    hw_shape*: hailo_3d_image_shape_t
  struct_hailo_stream_info_t_anon0_t* {.union, bycopy.} = object
    anon0*: struct_hailo_stream_info_t_anon0_t_anon0_t
    nms_info*: hailo_nms_info_t
  struct_hailo_stream_info_t* {.pure, inheritable, bycopy.} = object
    anon0*: struct_hailo_stream_info_t_anon0_t ## Generated based on /usr/include/hailo/hailort.h:1489:9
    hw_data_bytes*: uint32
    hw_frame_size*: uint32
    format*: hailo_format_t
    direction*: hailo_stream_direction_t
    index*: uint8
    name*: array[128'i64, cschar]
    quant_info*: hailo_quant_info_t
    is_mux*: bool
  hailo_stream_info_t* = struct_hailo_stream_info_t ## Generated based on /usr/include/hailo/hailort.h:1510:3
  struct_hailo_vstream_info_t_anon0_t* {.union, bycopy.} = object
    shape*: hailo_3d_image_shape_t
    nms_shape*: hailo_nms_shape_t
  struct_hailo_vstream_info_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1515:9
    network_name*: array[257'i64, cschar]
    direction*: hailo_stream_direction_t
    format*: hailo_format_t
    anon0*: struct_hailo_vstream_info_t_anon0_t
    quant_info*: hailo_quant_info_t
  hailo_vstream_info_t* = struct_hailo_vstream_info_t ## Generated based on /usr/include/hailo/hailort.h:1532:3
  hailo_power_mode_t* = enum_hailo_power_mode_t ## Generated based on /usr/include/hailo/hailort.h:1541:3
  hailo_latency_measurement_flags_t* = enum_hailo_latency_measurement_flags_t ## Generated based on /usr/include/hailo/hailort.h:1551:3
  struct_hailo_network_parameters_t* {.pure, inheritable, bycopy.} = object
    batch_size*: uint16      ## Generated based on /usr/include/hailo/hailort.h:1553:9
  hailo_network_parameters_t* = struct_hailo_network_parameters_t ## Generated based on /usr/include/hailo/hailort.h:1567:3
  struct_hailo_network_parameters_by_name_t* {.pure, inheritable, bycopy.} = object
    name*: array[257'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1569:9
    network_params*: hailo_network_parameters_t
  hailo_network_parameters_by_name_t* = struct_hailo_network_parameters_by_name_t ## Generated based on /usr/include/hailo/hailort.h:1572:3
  struct_hailo_configure_network_group_params_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1575:9
    batch_size*: uint16
    power_mode*: hailo_power_mode_t
    latency*: hailo_latency_measurement_flags_t
    stream_params_by_name_count*: csize_t
    stream_params_by_name*: array[40'i64, hailo_stream_parameters_by_name_t]
    network_params_by_name_count*: csize_t
    network_params_by_name*: array[8'i64, hailo_network_parameters_by_name_t]
  hailo_configure_network_group_params_t* = struct_hailo_configure_network_group_params_t ## Generated based on /usr/include/hailo/hailort.h:1585:3
  struct_hailo_configure_params_t* {.pure, inheritable, bycopy.} = object
    network_group_params_count*: csize_t ## Generated based on /usr/include/hailo/hailort.h:1588:9
    network_group_params*: array[8'i64, hailo_configure_network_group_params_t]
  hailo_configure_params_t* = struct_hailo_configure_params_t ## Generated based on /usr/include/hailo/hailort.h:1591:3
  struct_hailo_activate_network_group_params_t* {.pure, inheritable, bycopy.} = object
    reserved*: uint8         ## Generated based on /usr/include/hailo/hailort.h:1594:9
  hailo_activate_network_group_params_t* = struct_hailo_activate_network_group_params_t ## Generated based on /usr/include/hailo/hailort.h:1596:3
  struct_hailo_network_group_info_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1599:9
    is_multi_context*: bool
  hailo_network_group_info_t* = struct_hailo_network_group_info_t ## Generated based on /usr/include/hailo/hailort.h:1602:3
  struct_hailo_layer_name_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1605:9
  hailo_layer_name_t* = struct_hailo_layer_name_t ## Generated based on /usr/include/hailo/hailort.h:1607:3
  struct_hailo_network_info_t* {.pure, inheritable, bycopy.} = object
    name*: array[257'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1609:9
  hailo_network_info_t* = struct_hailo_network_info_t ## Generated based on /usr/include/hailo/hailort.h:1611:3
  hailo_notification_id_t* = enum_hailo_notification_id_t ## Generated based on /usr/include/hailo/hailort.h:1652:3
  struct_hailo_rx_error_notification_message_t* {.pure, inheritable, bycopy.} = object
    error*: uint32           ## Generated based on /usr/include/hailo/hailort.h:1655:9
    queue_number*: uint32
    rx_errors_count*: uint32
  hailo_rx_error_notification_message_t* = struct_hailo_rx_error_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1659:3
  struct_hailo_debug_notification_message_t* {.pure, inheritable, bycopy.} = object
    connection_status*: uint32 ## Generated based on /usr/include/hailo/hailort.h:1662:9
    connection_type*: uint32
    vdma_is_active*: uint32
    host_port*: uint32
    host_ip_addr*: uint32
  hailo_debug_notification_message_t* = struct_hailo_debug_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1668:3
  struct_hailo_health_monitor_dataflow_shutdown_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    ts0_temperature*: float32_t ## Generated based on /usr/include/hailo/hailort.h:1671:9
    ts1_temperature*: float32_t
  hailo_health_monitor_dataflow_shutdown_notification_message_t* = struct_hailo_health_monitor_dataflow_shutdown_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1674:3
  hailo_temperature_protection_temperature_zone_t* = enum_hailo_temperature_protection_temperature_zone_t ## Generated based on /usr/include/hailo/hailort.h:1680:3
  struct_hailo_health_monitor_temperature_alarm_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    temperature_zone*: hailo_temperature_protection_temperature_zone_t ## Generated based on /usr/include/hailo/hailort.h:1683:9
    alarm_ts_id*: uint32
    ts0_temperature*: float32_t
    ts1_temperature*: float32_t
  hailo_health_monitor_temperature_alarm_notification_message_t* = struct_hailo_health_monitor_temperature_alarm_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1688:3
  hailo_overcurrent_protection_overcurrent_zone_t* = enum_hailo_overcurrent_protection_overcurrent_zone_t ## Generated based on /usr/include/hailo/hailort.h:1693:3
  struct_hailo_health_monitor_overcurrent_alert_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    overcurrent_zone*: hailo_overcurrent_protection_overcurrent_zone_t ## Generated based on /usr/include/hailo/hailort.h:1696:9
    exceeded_alert_threshold*: float32_t
    is_last_overcurrent_violation_reached*: bool
  hailo_health_monitor_overcurrent_alert_notification_message_t* = struct_hailo_health_monitor_overcurrent_alert_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1700:3
  struct_hailo_health_monitor_lcu_ecc_error_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    cluster_error*: uint16   ## Generated based on /usr/include/hailo/hailort.h:1703:9
  hailo_health_monitor_lcu_ecc_error_notification_message_t* = struct_hailo_health_monitor_lcu_ecc_error_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1706:3
  struct_hailo_health_monitor_cpu_ecc_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    memory_bitmap*: uint32   ## Generated based on /usr/include/hailo/hailort.h:1709:9
  hailo_health_monitor_cpu_ecc_notification_message_t* = struct_hailo_health_monitor_cpu_ecc_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1711:3
  struct_hailo_performance_stats_t* {.pure, inheritable, bycopy.} = object
    cpu_utilization*: float32_t ## Generated based on /usr/include/hailo/hailort.h:1713:9
    ram_size_total*: int64
    ram_size_used*: int64
    nnc_utilization*: float32_t
    ddr_noc_total_transactions*: int32
    dsp_utilization*: int32
  hailo_performance_stats_t* = struct_hailo_performance_stats_t ## Generated based on /usr/include/hailo/hailort.h:1726:3
  struct_hailo_health_stats_t* {.pure, inheritable, bycopy.} = object
    on_die_temperature*: float32_t ## Generated based on /usr/include/hailo/hailort.h:1728:9
    on_die_voltage*: float32_t
    startup_bist_mask*: int32
  hailo_health_stats_t* = struct_hailo_health_stats_t ## Generated based on /usr/include/hailo/hailort.h:1732:3
  struct_hailo_context_switch_breakpoint_reached_message_t* {.pure, inheritable,
      bycopy.} = object
    network_group_index*: uint8 ## Generated based on /usr/include/hailo/hailort.h:1735:9
    batch_index*: uint16
    context_index*: uint16
    action_index*: uint16
  hailo_context_switch_breakpoint_reached_message_t* = struct_hailo_context_switch_breakpoint_reached_message_t ## Generated based on /usr/include/hailo/hailort.h:1740:3
  struct_hailo_health_monitor_clock_changed_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    previous_clock*: uint32  ## Generated based on /usr/include/hailo/hailort.h:1743:9
    current_clock*: uint32
  hailo_health_monitor_clock_changed_notification_message_t* = struct_hailo_health_monitor_clock_changed_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1746:3
  struct_hailo_hw_infer_manager_infer_done_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    infer_cycles*: uint32    ## Generated based on /usr/include/hailo/hailort.h:1748:9
  hailo_hw_infer_manager_infer_done_notification_message_t* = struct_hailo_hw_infer_manager_infer_done_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1750:3
  struct_hailo_start_update_cache_offset_notification_message_t* {.pure,
      inheritable, bycopy.} = object
    cache_id_bitmask*: uint64 ## Generated based on /usr/include/hailo/hailort.h:1752:9
  hailo_start_update_cache_offset_notification_message_t* = struct_hailo_start_update_cache_offset_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1754:3
  struct_hailo_context_switch_run_time_error_message_t* {.pure, inheritable,
      bycopy.} = object
    exit_status*: uint32     ## Generated based on /usr/include/hailo/hailort.h:1756:9
    network_group_index*: uint8
    batch_index*: uint16
    context_index*: uint16
    action_index*: uint16
  hailo_context_switch_run_time_error_message_t* = struct_hailo_context_switch_run_time_error_message_t ## Generated based on /usr/include/hailo/hailort.h:1762:3
  union_hailo_notification_message_parameters_t* {.union, bycopy.} = object
    rx_error_notification*: hailo_rx_error_notification_message_t ## Generated based on /usr/include/hailo/hailort.h:1765:9
    debug_notification*: hailo_debug_notification_message_t
    health_monitor_dataflow_shutdown_notification*: hailo_health_monitor_dataflow_shutdown_notification_message_t
    health_monitor_temperature_alarm_notification*: hailo_health_monitor_temperature_alarm_notification_message_t
    health_monitor_overcurrent_alert_notification*: hailo_health_monitor_overcurrent_alert_notification_message_t
    health_monitor_lcu_ecc_error_notification*: hailo_health_monitor_lcu_ecc_error_notification_message_t
    health_monitor_cpu_ecc_notification*: hailo_health_monitor_cpu_ecc_notification_message_t
    context_switch_breakpoint_reached_notification*: hailo_context_switch_breakpoint_reached_message_t
    health_monitor_clock_changed_notification*: hailo_health_monitor_clock_changed_notification_message_t
    hw_infer_manager_infer_done_notification*: hailo_hw_infer_manager_infer_done_notification_message_t
    context_switch_run_time_error*: hailo_context_switch_run_time_error_message_t
    start_update_cache_offset_notification*: hailo_start_update_cache_offset_notification_message_t
  hailo_notification_message_parameters_t* = union_hailo_notification_message_parameters_t ## Generated based on /usr/include/hailo/hailort.h:1790:3
  struct_hailo_notification_t* {.pure, inheritable, bycopy.} = object
    id*: hailo_notification_id_t ## Generated based on /usr/include/hailo/hailort.h:1793:9
    sequence*: uint32
    body*: hailo_notification_message_parameters_t
  hailo_notification_t* = struct_hailo_notification_t ## Generated based on /usr/include/hailo/hailort.h:1797:3
  hailo_notification_callback* = proc (a0: hailo_device;
                                       a1: ptr hailo_notification_t; a2: pointer): void {.
      cdecl.}                ## Generated based on /usr/include/hailo/hailort.h:1810:16
  hailo_reset_device_mode_t* = enum_hailo_reset_device_mode_t ## Generated based on /usr/include/hailo/hailort.h:1819:3
  hailo_watchdog_mode_t* = enum_hailo_watchdog_mode_t ## Generated based on /usr/include/hailo/hailort.h:1826:3
  struct_hailo_chip_temperature_info_t* {.pure, inheritable, bycopy.} = object
    ts0_temperature*: float32_t ## Generated based on /usr/include/hailo/hailort.h:1831:9
    ts1_temperature*: float32_t
    sample_count*: uint16
  hailo_chip_temperature_info_t* = struct_hailo_chip_temperature_info_t ## Generated based on /usr/include/hailo/hailort.h:1835:3
  struct_hailo_throttling_level_t* {.pure, inheritable, bycopy.} = object
    temperature_threshold*: float32_t ## Generated based on /usr/include/hailo/hailort.h:1837:9
    hysteresis_temperature_threshold*: float32_t
    throttling_nn_clock_freq*: uint32
  hailo_throttling_level_t* = struct_hailo_throttling_level_t ## Generated based on /usr/include/hailo/hailort.h:1841:3
  struct_hailo_health_info_t* {.pure, inheritable, bycopy.} = object
    overcurrent_protection_active*: bool ## Generated based on /usr/include/hailo/hailort.h:1843:9
    current_overcurrent_zone*: uint8
    red_overcurrent_threshold*: float32_t
    overcurrent_throttling_active*: bool
    temperature_throttling_active*: bool
    current_temperature_zone*: uint8
    current_temperature_throttling_level*: int8
    temperature_throttling_levels*: array[4'i64, hailo_throttling_level_t]
    orange_temperature_threshold*: int32
    orange_hysteresis_temperature_threshold*: int32
    red_temperature_threshold*: int32
    red_hysteresis_temperature_threshold*: int32
    requested_overcurrent_clock_freq*: uint32
    requested_temperature_clock_freq*: uint32
  hailo_health_info_t* = struct_hailo_health_info_t ## Generated based on /usr/include/hailo/hailort.h:1858:3
  struct_hailo_stream_raw_buffer_t* {.pure, inheritable, bycopy.} = object
    buffer*: pointer         ## Generated based on /usr/include/hailo/hailort.h:1860:9
    size*: csize_t
  hailo_stream_raw_buffer_t* = struct_hailo_stream_raw_buffer_t ## Generated based on /usr/include/hailo/hailort.h:1863:3
  struct_hailo_stream_raw_buffer_by_name_t* {.pure, inheritable, bycopy.} = object
    name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1865:9
    raw_buffer*: hailo_stream_raw_buffer_t
  hailo_stream_raw_buffer_by_name_t* = struct_hailo_stream_raw_buffer_by_name_t ## Generated based on /usr/include/hailo/hailort.h:1868:3
  struct_hailo_latency_measurement_result_t* {.pure, inheritable, bycopy.} = object
    avg_hw_latency_ms*: float64_t ## Generated based on /usr/include/hailo/hailort.h:1870:9
  hailo_latency_measurement_result_t* = struct_hailo_latency_measurement_result_t ## Generated based on /usr/include/hailo/hailort.h:1872:3
  struct_hailo_rate_limit_t* {.pure, inheritable, bycopy.} = object
    stream_name*: array[128'i64, cschar] ## Generated based on /usr/include/hailo/hailort.h:1874:9
    rate*: uint32
  hailo_rate_limit_t* = struct_hailo_rate_limit_t ## Generated based on /usr/include/hailo/hailort.h:1877:3
  hailo_sensor_types_t* = enum_hailo_sensor_types_t ## Generated based on /usr/include/hailo/hailort.h:1888:3
  hailo_fw_logger_interface_t* = enum_hailo_fw_logger_interface_t ## Generated based on /usr/include/hailo/hailort.h:1896:3
  hailo_fw_logger_level_t* = enum_hailo_fw_logger_level_t ## Generated based on /usr/include/hailo/hailort.h:1908:3
  hailo_sleep_state_t* = enum_hailo_sleep_state_e ## Generated based on /usr/include/hailo/hailort.h:4139:3
  sa_family_t* = cushort     ## Generated based on /usr/include/x86_64-linux-gnu/bits/sockaddr.h:28:28
  in_port_t* = uint16        ## Generated based on /usr/include/netinet/in.h:125:18
  struct_in_addr* {.pure, inheritable, bycopy.} = object
    s_addr*: in_addr_t       ## Generated based on /usr/include/netinet/in.h:31:8
  in_addr_t* = uint32        ## Generated based on /usr/include/netinet/in.h:30:18
when cast[cuint](4294967295'i64) is static:
  const
    UINT32_MAX* = cast[cuint](4294967295'i64) ## Generated based on /usr/include/stdint.h:118:10
else:
  let UINT32_MAX* = cast[cuint](4294967295'i64) ## Generated based on /usr/include/stdint.h:118:10
when 10000 is static:
  const
    HAILO_DEFAULT_ETH_SCAN_TIMEOUT_MS* = 10000 ## Generated based on /usr/include/hailo/hailort.h:33:9
else:
  let HAILO_DEFAULT_ETH_SCAN_TIMEOUT_MS* = 10000 ## Generated based on /usr/include/hailo/hailort.h:33:9
when 22401 is static:
  const
    HAILO_DEFAULT_ETH_CONTROL_PORT* = 22401 ## Generated based on /usr/include/hailo/hailort.h:34:9
else:
  let HAILO_DEFAULT_ETH_CONTROL_PORT* = 22401 ## Generated based on /usr/include/hailo/hailort.h:34:9
when 0 is static:
  const
    HAILO_DEFAULT_ETH_DEVICE_PORT* = 0 ## Generated based on /usr/include/hailo/hailort.h:35:9
else:
  let HAILO_DEFAULT_ETH_DEVICE_PORT* = 0 ## Generated based on /usr/include/hailo/hailort.h:35:9
when 1456 is static:
  const
    HAILO_DEFAULT_ETH_MAX_PAYLOAD_SIZE* = 1456 ## Generated based on /usr/include/hailo/hailort.h:36:9
else:
  let HAILO_DEFAULT_ETH_MAX_PAYLOAD_SIZE* = 1456 ## Generated based on /usr/include/hailo/hailort.h:36:9
when 3 is static:
  const
    HAILO_DEFAULT_ETH_MAX_NUMBER_OF_RETRIES* = 3 ## Generated based on /usr/include/hailo/hailort.h:37:9
else:
  let HAILO_DEFAULT_ETH_MAX_NUMBER_OF_RETRIES* = 3 ## Generated based on /usr/include/hailo/hailort.h:37:9
when "0.0.0.0" is static:
  const
    HAILO_ETH_ADDRESS_ANY* = "0.0.0.0" ## Generated based on /usr/include/hailo/hailort.h:38:9
else:
  let HAILO_ETH_ADDRESS_ANY* = "0.0.0.0" ## Generated based on /usr/include/hailo/hailort.h:38:9
when 0 is static:
  const
    HAILO_ETH_PORT_ANY* = 0  ## Generated based on /usr/include/hailo/hailort.h:39:9
else:
  let HAILO_ETH_PORT_ANY* = 0 ## Generated based on /usr/include/hailo/hailort.h:39:9
when 128 is static:
  const
    HAILO_MAX_NAME_SIZE* = 128 ## Generated based on /usr/include/hailo/hailort.h:40:9
else:
  let HAILO_MAX_NAME_SIZE* = 128 ## Generated based on /usr/include/hailo/hailort.h:40:9
when HAILO_MAX_NAME_SIZE is typedesc:
  type
    HAILO_MAX_STREAM_NAME_SIZE* = HAILO_MAX_NAME_SIZE ## Generated based on /usr/include/hailo/hailort.h:41:9
else:
  when HAILO_MAX_NAME_SIZE is static:
    const
      HAILO_MAX_STREAM_NAME_SIZE* = HAILO_MAX_NAME_SIZE ## Generated based on /usr/include/hailo/hailort.h:41:9
  else:
    let HAILO_MAX_STREAM_NAME_SIZE* = HAILO_MAX_NAME_SIZE ## Generated based on /usr/include/hailo/hailort.h:41:9
when 32 is static:
  const
    HAILO_MAX_BOARD_NAME_LENGTH* = 32 ## Generated based on /usr/include/hailo/hailort.h:42:9
else:
  let HAILO_MAX_BOARD_NAME_LENGTH* = 32 ## Generated based on /usr/include/hailo/hailort.h:42:9
when 32 is static:
  const
    HAILO_MAX_DEVICE_ID_LENGTH* = 32 ## Generated based on /usr/include/hailo/hailort.h:43:9
else:
  let HAILO_MAX_DEVICE_ID_LENGTH* = 32 ## Generated based on /usr/include/hailo/hailort.h:43:9
when 16 is static:
  const
    HAILO_MAX_SERIAL_NUMBER_LENGTH* = 16 ## Generated based on /usr/include/hailo/hailort.h:44:9
else:
  let HAILO_MAX_SERIAL_NUMBER_LENGTH* = 16 ## Generated based on /usr/include/hailo/hailort.h:44:9
when 16 is static:
  const
    HAILO_MAX_PART_NUMBER_LENGTH* = 16 ## Generated based on /usr/include/hailo/hailort.h:45:9
else:
  let HAILO_MAX_PART_NUMBER_LENGTH* = 16 ## Generated based on /usr/include/hailo/hailort.h:45:9
when 42 is static:
  const
    HAILO_MAX_PRODUCT_NAME_LENGTH* = 42 ## Generated based on /usr/include/hailo/hailort.h:46:9
else:
  let HAILO_MAX_PRODUCT_NAME_LENGTH* = 42 ## Generated based on /usr/include/hailo/hailort.h:46:9
when HAILO_SAMPLING_PERIOD_1100US is typedesc:
  type
    HAILO_DEFAULT_INIT_SAMPLING_PERIOD_US* = HAILO_SAMPLING_PERIOD_1100US ## Generated based on /usr/include/hailo/hailort.h:47:9
else:
  when HAILO_SAMPLING_PERIOD_1100US is static:
    const
      HAILO_DEFAULT_INIT_SAMPLING_PERIOD_US* = HAILO_SAMPLING_PERIOD_1100US ## Generated based on /usr/include/hailo/hailort.h:47:9
  else:
    let HAILO_DEFAULT_INIT_SAMPLING_PERIOD_US* = HAILO_SAMPLING_PERIOD_1100US ## Generated based on /usr/include/hailo/hailort.h:47:9
when HAILO_AVERAGE_FACTOR_256 is typedesc:
  type
    HAILO_DEFAULT_INIT_AVERAGING_FACTOR* = HAILO_AVERAGE_FACTOR_256 ## Generated based on /usr/include/hailo/hailort.h:48:9
else:
  when HAILO_AVERAGE_FACTOR_256 is static:
    const
      HAILO_DEFAULT_INIT_AVERAGING_FACTOR* = HAILO_AVERAGE_FACTOR_256 ## Generated based on /usr/include/hailo/hailort.h:48:9
  else:
    let HAILO_DEFAULT_INIT_AVERAGING_FACTOR* = HAILO_AVERAGE_FACTOR_256 ## Generated based on /usr/include/hailo/hailort.h:48:9
when 0 is static:
  const
    HAILO_DEFAULT_BUFFERS_THRESHOLD* = 0 ## Generated based on /usr/include/hailo/hailort.h:49:9
else:
  let HAILO_DEFAULT_BUFFERS_THRESHOLD* = 0 ## Generated based on /usr/include/hailo/hailort.h:49:9
when 106300000 is static:
  const
    HAILO_DEFAULT_MAX_ETHERNET_BANDWIDTH_BYTES_PER_SEC* = 106300000 ## Generated based on /usr/include/hailo/hailort.h:50:9
else:
  let HAILO_DEFAULT_MAX_ETHERNET_BANDWIDTH_BYTES_PER_SEC* = 106300000 ## Generated based on /usr/include/hailo/hailort.h:50:9
when 40 is static:
  const
    HAILO_MAX_STREAMS_COUNT* = 40 ## Generated based on /usr/include/hailo/hailort.h:51:9
else:
  let HAILO_MAX_STREAMS_COUNT* = 40 ## Generated based on /usr/include/hailo/hailort.h:51:9
when 0 is static:
  const
    HAILO_DEFAULT_BATCH_SIZE* = 0 ## Generated based on /usr/include/hailo/hailort.h:52:9
else:
  let HAILO_DEFAULT_BATCH_SIZE* = 0 ## Generated based on /usr/include/hailo/hailort.h:52:9
when 8 is static:
  const
    HAILO_MAX_NETWORK_GROUPS* = 8 ## Generated based on /usr/include/hailo/hailort.h:53:9
else:
  let HAILO_MAX_NETWORK_GROUPS* = 8 ## Generated based on /usr/include/hailo/hailort.h:53:9
when HAILO_MAX_NAME_SIZE is typedesc:
  type
    HAILO_MAX_NETWORK_GROUP_NAME_SIZE* = HAILO_MAX_NAME_SIZE ## Generated based on /usr/include/hailo/hailort.h:54:9
else:
  when HAILO_MAX_NAME_SIZE is static:
    const
      HAILO_MAX_NETWORK_GROUP_NAME_SIZE* = HAILO_MAX_NAME_SIZE ## Generated based on /usr/include/hailo/hailort.h:54:9
  else:
    let HAILO_MAX_NETWORK_GROUP_NAME_SIZE* = HAILO_MAX_NAME_SIZE ## Generated based on /usr/include/hailo/hailort.h:54:9
when 8 is static:
  const
    HAILO_MAX_NETWORKS_IN_NETWORK_GROUP* = 8 ## Generated based on /usr/include/hailo/hailort.h:57:9
else:
  let HAILO_MAX_NETWORKS_IN_NETWORK_GROUP* = 8 ## Generated based on /usr/include/hailo/hailort.h:57:9
when UINT32_MAX is typedesc:
  type
    HAILO_PCIE_ANY_DOMAIN* = UINT32_MAX ## Generated based on /usr/include/hailo/hailort.h:58:9
else:
  when UINT32_MAX is static:
    const
      HAILO_PCIE_ANY_DOMAIN* = UINT32_MAX ## Generated based on /usr/include/hailo/hailort.h:58:9
  else:
    let HAILO_PCIE_ANY_DOMAIN* = UINT32_MAX ## Generated based on /usr/include/hailo/hailort.h:58:9
when 2 is static:
  const
    HAILO_DEFAULT_VSTREAM_QUEUE_SIZE* = 2 ## Generated based on /usr/include/hailo/hailort.h:59:9
else:
  let HAILO_DEFAULT_VSTREAM_QUEUE_SIZE* = 2 ## Generated based on /usr/include/hailo/hailort.h:59:9
when 10000 is static:
  const
    HAILO_DEFAULT_VSTREAM_TIMEOUT_MS* = 10000 ## Generated based on /usr/include/hailo/hailort.h:60:9
else:
  let HAILO_DEFAULT_VSTREAM_TIMEOUT_MS* = 10000 ## Generated based on /usr/include/hailo/hailort.h:60:9
when 10000 is static:
  const
    HAILO_DEFAULT_ASYNC_INFER_TIMEOUT_MS* = 10000 ## Generated based on /usr/include/hailo/hailort.h:61:9
else:
  let HAILO_DEFAULT_ASYNC_INFER_TIMEOUT_MS* = 10000 ## Generated based on /usr/include/hailo/hailort.h:61:9
when 2 is static:
  const
    HAILO_DEFAULT_ASYNC_INFER_QUEUE_SIZE* = 2 ## Generated based on /usr/include/hailo/hailort.h:62:9
else:
  let HAILO_DEFAULT_ASYNC_INFER_QUEUE_SIZE* = 2 ## Generated based on /usr/include/hailo/hailort.h:62:9
when 1 is static:
  const
    HAILO_DEFAULT_DEVICE_COUNT* = 1 ## Generated based on /usr/include/hailo/hailort.h:63:9
else:
  let HAILO_DEFAULT_DEVICE_COUNT* = 1 ## Generated based on /usr/include/hailo/hailort.h:63:9
when 32 is static:
  const
    HAILO_SOC_ID_LENGTH* = 32 ## Generated based on /usr/include/hailo/hailort.h:65:9
else:
  let HAILO_SOC_ID_LENGTH* = 32 ## Generated based on /usr/include/hailo/hailort.h:65:9
when 6 is static:
  const
    HAILO_ETH_MAC_LENGTH* = 6 ## Generated based on /usr/include/hailo/hailort.h:66:9
else:
  let HAILO_ETH_MAC_LENGTH* = 6 ## Generated based on /usr/include/hailo/hailort.h:66:9
when 12 is static:
  const
    HAILO_UNIT_LEVEL_TRACKING_BYTES_LENGTH* = 12 ## Generated based on /usr/include/hailo/hailort.h:67:9
else:
  let HAILO_UNIT_LEVEL_TRACKING_BYTES_LENGTH* = 12 ## Generated based on /usr/include/hailo/hailort.h:67:9
when 24 is static:
  const
    HAILO_SOC_PM_VALUES_BYTES_LENGTH* = 24 ## Generated based on /usr/include/hailo/hailort.h:68:9
else:
  let HAILO_SOC_PM_VALUES_BYTES_LENGTH* = 24 ## Generated based on /usr/include/hailo/hailort.h:68:9
when 16 is static:
  const
    HAILO_GPIO_MASK_VALUES_LENGTH* = 16 ## Generated based on /usr/include/hailo/hailort.h:69:9
else:
  let HAILO_GPIO_MASK_VALUES_LENGTH* = 16 ## Generated based on /usr/include/hailo/hailort.h:69:9
when 4 is static:
  const
    HAILO_MAX_TEMPERATURE_THROTTLING_LEVELS_NUMBER* = 4 ## Generated based on /usr/include/hailo/hailort.h:70:9
else:
  let HAILO_MAX_TEMPERATURE_THROTTLING_LEVELS_NUMBER* = 4 ## Generated based on /usr/include/hailo/hailort.h:70:9
when "UNIQUE" is static:
  const
    HAILO_UNIQUE_VDEVICE_GROUP_ID* = "UNIQUE" ## Generated based on /usr/include/hailo/hailort.h:72:9
else:
  let HAILO_UNIQUE_VDEVICE_GROUP_ID* = "UNIQUE" ## Generated based on /usr/include/hailo/hailort.h:72:9
when HAILO_UNIQUE_VDEVICE_GROUP_ID is typedesc:
  type
    HAILO_DEFAULT_VDEVICE_GROUP_ID* = HAILO_UNIQUE_VDEVICE_GROUP_ID ## Generated based on /usr/include/hailo/hailort.h:73:9
else:
  when HAILO_UNIQUE_VDEVICE_GROUP_ID is static:
    const
      HAILO_DEFAULT_VDEVICE_GROUP_ID* = HAILO_UNIQUE_VDEVICE_GROUP_ID ## Generated based on /usr/include/hailo/hailort.h:73:9
  else:
    let HAILO_DEFAULT_VDEVICE_GROUP_ID* = HAILO_UNIQUE_VDEVICE_GROUP_ID ## Generated based on /usr/include/hailo/hailort.h:73:9
when 16 is static:
  const
    HAILO_SCHEDULER_PRIORITY_NORMAL* = 16 ## Generated based on /usr/include/hailo/hailort.h:75:9
else:
  let HAILO_SCHEDULER_PRIORITY_NORMAL* = 16 ## Generated based on /usr/include/hailo/hailort.h:75:9
when 31 is static:
  const
    HAILO_SCHEDULER_PRIORITY_MAX* = 31 ## Generated based on /usr/include/hailo/hailort.h:76:9
else:
  let HAILO_SCHEDULER_PRIORITY_MAX* = 31 ## Generated based on /usr/include/hailo/hailort.h:76:9
when 0 is static:
  const
    HAILO_SCHEDULER_PRIORITY_MIN* = 0 ## Generated based on /usr/include/hailo/hailort.h:77:9
else:
  let HAILO_SCHEDULER_PRIORITY_MIN* = 0 ## Generated based on /usr/include/hailo/hailort.h:77:9
when 4 is static:
  const
    MAX_NUMBER_OF_PLANES* = 4 ## Generated based on /usr/include/hailo/hailort.h:79:9
else:
  let MAX_NUMBER_OF_PLANES* = 4 ## Generated based on /usr/include/hailo/hailort.h:79:9
when 2 is static:
  const
    NUMBER_OF_PLANES_NV12_NV21* = 2 ## Generated based on /usr/include/hailo/hailort.h:80:9
else:
  let NUMBER_OF_PLANES_NV12_NV21* = 2 ## Generated based on /usr/include/hailo/hailort.h:80:9
when 3 is static:
  const
    NUMBER_OF_PLANES_I420* = 3 ## Generated based on /usr/include/hailo/hailort.h:81:9
else:
  let NUMBER_OF_PLANES_I420* = 3 ## Generated based on /usr/include/hailo/hailort.h:81:9
when HAILO_STREAM_ABORT is typedesc:
  type
    HAILO_STREAM_ABORTED_BY_USER* = HAILO_STREAM_ABORT ## Generated based on /usr/include/hailo/hailort.h:196:9
else:
  when HAILO_STREAM_ABORT is static:
    const
      HAILO_STREAM_ABORTED_BY_USER* = HAILO_STREAM_ABORT ## Generated based on /usr/include/hailo/hailort.h:196:9
  else:
    let HAILO_STREAM_ABORTED_BY_USER* = HAILO_STREAM_ABORT ## Generated based on /usr/include/hailo/hailort.h:196:9
when HAILO_DRIVER_OPERATION_FAILED is typedesc:
  type
    HAILO_DRIVER_FAIL* = HAILO_DRIVER_OPERATION_FAILED ## Generated based on /usr/include/hailo/hailort.h:197:9
else:
  when HAILO_DRIVER_OPERATION_FAILED is static:
    const
      HAILO_DRIVER_FAIL* = HAILO_DRIVER_OPERATION_FAILED ## Generated based on /usr/include/hailo/hailort.h:197:9
  else:
    let HAILO_DRIVER_FAIL* = HAILO_DRIVER_OPERATION_FAILED ## Generated based on /usr/include/hailo/hailort.h:197:9
when HAILO_DRIVER_NOT_INSTALLED is typedesc:
  type
    HAILO_PCIE_DRIVER_NOT_INSTALLED* = HAILO_DRIVER_NOT_INSTALLED ## Generated based on /usr/include/hailo/hailort.h:198:9
else:
  when HAILO_DRIVER_NOT_INSTALLED is static:
    const
      HAILO_PCIE_DRIVER_NOT_INSTALLED* = HAILO_DRIVER_NOT_INSTALLED ## Generated based on /usr/include/hailo/hailort.h:198:9
  else:
    let HAILO_PCIE_DRIVER_NOT_INSTALLED* = HAILO_DRIVER_NOT_INSTALLED ## Generated based on /usr/include/hailo/hailort.h:198:9
proc hailo_get_library_version*(version: ptr hailo_version_t): hailo_status {.
    cdecl, importc: "hailo_get_library_version".}
proc hailo_get_status_message*(status: hailo_status): cstring {.cdecl,
    importc: "hailo_get_status_message".}
proc hailo_scan_devices*(params: ptr hailo_scan_devices_params_t;
                         device_ids: ptr hailo_device_id_t;
                         device_ids_length: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_scan_devices".}
proc hailo_create_device_by_id*(device_id: ptr hailo_device_id_t;
                                device: ptr hailo_device): hailo_status {.cdecl,
    importc: "hailo_create_device_by_id".}
proc hailo_scan_pcie_devices*(pcie_device_infos: ptr hailo_pcie_device_info_t;
                              pcie_device_infos_length: csize_t;
                              number_of_devices: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_scan_pcie_devices".}
proc hailo_parse_pcie_device_info*(device_info_str: cstring;
                                   device_info: ptr hailo_pcie_device_info_t): hailo_status {.
    cdecl, importc: "hailo_parse_pcie_device_info".}
proc hailo_create_pcie_device*(device_info: ptr hailo_pcie_device_info_t;
                               device: ptr hailo_device): hailo_status {.cdecl,
    importc: "hailo_create_pcie_device".}
proc hailo_scan_ethernet_devices*(interface_name: cstring; eth_device_infos: ptr hailo_eth_device_info_t;
                                  eth_device_infos_length: csize_t;
                                  number_of_devices: ptr csize_t;
                                  timeout_ms: uint32): hailo_status {.cdecl,
    importc: "hailo_scan_ethernet_devices".}
proc hailo_create_ethernet_device*(device_info: ptr hailo_eth_device_info_t;
                                   device: ptr hailo_device): hailo_status {.
    cdecl, importc: "hailo_create_ethernet_device".}
proc hailo_release_device*(device: hailo_device): hailo_status {.cdecl,
    importc: "hailo_release_device".}
proc hailo_device_get_type_by_device_id*(device_id: ptr hailo_device_id_t;
    device_type: ptr hailo_device_type_t): hailo_status {.cdecl,
    importc: "hailo_device_get_type_by_device_id".}
proc hailo_identify*(device: hailo_device;
                     device_identity: ptr hailo_device_identity_t): hailo_status {.
    cdecl, importc: "hailo_identify".}
proc hailo_core_identify*(device: hailo_device;
                          core_information: ptr hailo_core_information_t): hailo_status {.
    cdecl, importc: "hailo_core_identify".}
proc hailo_get_extended_device_information*(device: hailo_device;
    extended_device_information: ptr hailo_extended_device_information_t): hailo_status {.
    cdecl, importc: "hailo_get_extended_device_information".}
proc hailo_set_fw_logger*(device: hailo_device; level: hailo_fw_logger_level_t;
                          interface_mask: uint32): hailo_status {.cdecl,
    importc: "hailo_set_fw_logger".}
proc hailo_set_throttling_state*(device: hailo_device; should_activate: bool): hailo_status {.
    cdecl, importc: "hailo_set_throttling_state".}
proc hailo_get_throttling_state*(device: hailo_device; is_active: ptr bool): hailo_status {.
    cdecl, importc: "hailo_get_throttling_state".}
proc hailo_wd_enable*(device: hailo_device; cpu_id: hailo_cpu_id_t): hailo_status {.
    cdecl, importc: "hailo_wd_enable".}
proc hailo_wd_disable*(device: hailo_device; cpu_id: hailo_cpu_id_t): hailo_status {.
    cdecl, importc: "hailo_wd_disable".}
proc hailo_wd_config*(device: hailo_device; cpu_id: hailo_cpu_id_t;
                      wd_cycles: uint32; wd_mode: hailo_watchdog_mode_t): hailo_status {.
    cdecl, importc: "hailo_wd_config".}
proc hailo_get_previous_system_state*(device: hailo_device;
                                      cpu_id: hailo_cpu_id_t;
                                      previous_system_state: ptr uint32): hailo_status {.
    cdecl, importc: "hailo_get_previous_system_state".}
proc hailo_set_pause_frames*(device: hailo_device; rx_pause_frames_enable: bool): hailo_status {.
    cdecl, importc: "hailo_set_pause_frames".}
proc hailo_get_device_id*(device: hailo_device; id: ptr hailo_device_id_t): hailo_status {.
    cdecl, importc: "hailo_get_device_id".}
proc hailo_get_chip_temperature*(device: hailo_device;
                                 temp_info: ptr hailo_chip_temperature_info_t): hailo_status {.
    cdecl, importc: "hailo_get_chip_temperature".}
proc hailo_reset_device*(device: hailo_device; mode: hailo_reset_device_mode_t): hailo_status {.
    cdecl, importc: "hailo_reset_device".}
proc hailo_update_firmware*(device: hailo_device; firmware_buffer: pointer;
                            firmware_buffer_size: uint32): hailo_status {.cdecl,
    importc: "hailo_update_firmware".}
proc hailo_update_second_stage*(device: hailo_device;
                                second_stage_buffer: pointer;
                                second_stage_buffer_size: uint32): hailo_status {.
    cdecl, importc: "hailo_update_second_stage".}
proc hailo_set_notification_callback*(device: hailo_device;
                                      callback: hailo_notification_callback;
                                      notification_id: hailo_notification_id_t;
                                      opaque: pointer): hailo_status {.cdecl,
    importc: "hailo_set_notification_callback".}
proc hailo_remove_notification_callback*(device: hailo_device;
    notification_id: hailo_notification_id_t): hailo_status {.cdecl,
    importc: "hailo_remove_notification_callback".}
proc hailo_reset_sensor*(device: hailo_device; section_index: uint8): hailo_status {.
    cdecl, importc: "hailo_reset_sensor".}
proc hailo_set_sensor_i2c_bus_index*(device: hailo_device;
                                     sensor_type: hailo_sensor_types_t;
                                     bus_index: uint8): hailo_status {.cdecl,
    importc: "hailo_set_sensor_i2c_bus_index".}
proc hailo_load_and_start_sensor*(device: hailo_device; section_index: uint8): hailo_status {.
    cdecl, importc: "hailo_load_and_start_sensor".}
proc hailo_i2c_read*(device: hailo_device;
                     slave_config: ptr hailo_i2c_slave_config_t;
                     register_address: uint32; data: ptr uint8; length: uint32): hailo_status {.
    cdecl, importc: "hailo_i2c_read".}
proc hailo_i2c_write*(device: hailo_device;
                      slave_config: ptr hailo_i2c_slave_config_t;
                      register_address: uint32; data: ptr uint8; length: uint32): hailo_status {.
    cdecl, importc: "hailo_i2c_write".}
proc hailo_dump_sensor_config*(device: hailo_device; section_index: uint8;
                               config_file_path: cstring): hailo_status {.cdecl,
    importc: "hailo_dump_sensor_config".}
proc hailo_store_sensor_config*(device: hailo_device; section_index: uint32;
                                sensor_type: hailo_sensor_types_t;
                                reset_config_size: uint32;
                                config_height: uint16; config_width: uint16;
                                config_fps: uint16; config_file_path: cstring;
                                config_name: cstring): hailo_status {.cdecl,
    importc: "hailo_store_sensor_config".}
proc hailo_store_isp_config*(device: hailo_device; reset_config_size: uint32;
                             config_height: uint16; config_width: uint16;
                             config_fps: uint16;
                             isp_static_config_file_path: cstring;
                             isp_runtime_config_file_path: cstring;
                             config_name: cstring): hailo_status {.cdecl,
    importc: "hailo_store_isp_config".}
proc hailo_test_chip_memories*(device: hailo_device): hailo_status {.cdecl,
    importc: "hailo_test_chip_memories".}
proc hailo_init_vdevice_params*(params: ptr hailo_vdevice_params_t): hailo_status {.
    cdecl, importc: "hailo_init_vdevice_params".}
proc hailo_create_vdevice*(params: ptr hailo_vdevice_params_t;
                           vdevice: ptr hailo_vdevice): hailo_status {.cdecl,
    importc: "hailo_create_vdevice".}
proc hailo_configure_vdevice*(vdevice: hailo_vdevice; hef: hailo_hef;
                              params: ptr hailo_configure_params_t;
    network_groups: ptr hailo_configured_network_group;
                              number_of_network_groups: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_configure_vdevice".}
proc hailo_get_physical_devices*(vdevice: hailo_vdevice;
                                 devices: ptr hailo_device;
                                 number_of_devices: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_physical_devices".}
proc hailo_vdevice_get_physical_devices_ids*(vdevice: hailo_vdevice;
    devices_ids: ptr hailo_device_id_t; number_of_devices: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_vdevice_get_physical_devices_ids".}
proc hailo_release_vdevice*(vdevice: hailo_vdevice): hailo_status {.cdecl,
    importc: "hailo_release_vdevice".}
proc hailo_power_measurement*(device: hailo_device; dvm: hailo_dvm_options_t;
    measurement_type: hailo_power_measurement_types_t;
                              measurement: ptr float32_t): hailo_status {.cdecl,
    importc: "hailo_power_measurement".}
proc hailo_start_power_measurement*(device: hailo_device;
                                    averaging_factor: hailo_averaging_factor_t;
                                    sampling_period: hailo_sampling_period_t): hailo_status {.
    cdecl, importc: "hailo_start_power_measurement".}
proc hailo_set_power_measurement*(device: hailo_device; buffer_index: hailo_measurement_buffer_index_t;
                                  dvm: hailo_dvm_options_t; measurement_type: hailo_power_measurement_types_t): hailo_status {.
    cdecl, importc: "hailo_set_power_measurement".}
proc hailo_get_power_measurement*(device: hailo_device; buffer_index: hailo_measurement_buffer_index_t;
                                  should_clear: bool; measurement_data: ptr hailo_power_measurement_data_t): hailo_status {.
    cdecl, importc: "hailo_get_power_measurement".}
proc hailo_stop_power_measurement*(device: hailo_device): hailo_status {.cdecl,
    importc: "hailo_stop_power_measurement".}
proc hailo_create_hef_file*(hef: ptr hailo_hef; file_name: cstring): hailo_status {.
    cdecl, importc: "hailo_create_hef_file".}
proc hailo_create_hef_buffer*(hef: ptr hailo_hef; buffer: pointer; size: csize_t): hailo_status {.
    cdecl, importc: "hailo_create_hef_buffer".}
proc hailo_release_hef*(hef: hailo_hef): hailo_status {.cdecl,
    importc: "hailo_release_hef".}
proc hailo_hef_get_all_stream_infos*(hef: hailo_hef; name: cstring;
                                     stream_infos: ptr hailo_stream_info_t;
                                     stream_infos_length: csize_t;
                                     number_of_streams: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_all_stream_infos".}
proc hailo_hef_get_stream_info_by_name*(hef: hailo_hef;
                                        network_group_name: cstring;
                                        stream_name: cstring; stream_direction: hailo_stream_direction_t;
                                        stream_info: ptr hailo_stream_info_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_stream_info_by_name".}
proc hailo_hef_get_all_vstream_infos*(hef: hailo_hef; name: cstring;
                                      vstream_infos: ptr hailo_vstream_info_t;
                                      vstream_infos_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_all_vstream_infos".}
proc hailo_hef_get_vstream_name_from_original_name*(hef: hailo_hef;
    network_group_name: cstring; original_name: cstring;
    vstream_name: ptr hailo_layer_name_t): hailo_status {.cdecl,
    importc: "hailo_hef_get_vstream_name_from_original_name".}
proc hailo_hef_get_original_names_from_vstream_name*(hef: hailo_hef;
    network_group_name: cstring; vstream_name: cstring;
    original_names: ptr hailo_layer_name_t; original_names_length: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_original_names_from_vstream_name".}
proc hailo_hef_get_vstream_names_from_stream_name*(hef: hailo_hef;
    network_group_name: cstring; stream_name: cstring;
    vstream_names: ptr hailo_layer_name_t; vstream_names_length: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_vstream_names_from_stream_name".}
proc hailo_hef_get_stream_names_from_vstream_name*(hef: hailo_hef;
    network_group_name: cstring; vstream_name: cstring;
    stream_names: ptr hailo_layer_name_t; stream_names_length: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_stream_names_from_vstream_name".}
proc hailo_hef_get_sorted_output_names*(hef: hailo_hef;
                                        network_group_name: cstring;
    sorted_output_names: ptr hailo_layer_name_t;
                                        sorted_output_names_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_sorted_output_names".}
proc hailo_hef_get_bottleneck_fps*(hef: hailo_hef; network_group_name: cstring;
                                   bottleneck_fps: ptr float64_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_bottleneck_fps".}
proc hailo_calculate_eth_input_rate_limits*(hef: hailo_hef;
    network_group_name: cstring; fps: uint32; rates: ptr hailo_rate_limit_t;
    rates_length: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_calculate_eth_input_rate_limits".}
proc hailo_init_configure_params*(hef: hailo_hef;
                                  stream_interface: hailo_stream_interface_t;
                                  params: ptr hailo_configure_params_t): hailo_status {.
    cdecl, importc: "hailo_init_configure_params".}
proc hailo_init_configure_params_by_vdevice*(hef: hailo_hef;
    vdevice: hailo_vdevice; params: ptr hailo_configure_params_t): hailo_status {.
    cdecl, importc: "hailo_init_configure_params_by_vdevice".}
proc hailo_init_configure_params_by_device*(hef: hailo_hef;
    device: hailo_device; params: ptr hailo_configure_params_t): hailo_status {.
    cdecl, importc: "hailo_init_configure_params_by_device".}
proc hailo_init_configure_params_mipi_input*(hef: hailo_hef;
    output_interface: hailo_stream_interface_t;
    mipi_params: ptr hailo_mipi_input_stream_params_t;
    params: ptr hailo_configure_params_t): hailo_status {.cdecl,
    importc: "hailo_init_configure_params_mipi_input".}
proc hailo_init_configure_network_group_params*(hef: hailo_hef;
    stream_interface: hailo_stream_interface_t; network_group_name: cstring;
    params: ptr hailo_configure_network_group_params_t): hailo_status {.cdecl,
    importc: "hailo_init_configure_network_group_params".}
proc hailo_init_configure_network_group_params_mipi_input*(hef: hailo_hef;
    output_interface: hailo_stream_interface_t;
    mipi_params: ptr hailo_mipi_input_stream_params_t;
    network_group_name: cstring;
    params: ptr hailo_configure_network_group_params_t): hailo_status {.cdecl,
    importc: "hailo_init_configure_network_group_params_mipi_input".}
proc hailo_configure_device*(device: hailo_device; hef: hailo_hef;
                             params: ptr hailo_configure_params_t;
    network_groups: ptr hailo_configured_network_group;
                             number_of_network_groups: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_configure_device".}
proc hailo_wait_for_network_group_activation*(
    network_group: hailo_configured_network_group; timeout_ms: uint32): hailo_status {.
    cdecl, importc: "hailo_wait_for_network_group_activation".}
proc hailo_get_network_groups_infos*(hef: hailo_hef;
                                     infos: ptr hailo_network_group_info_t;
                                     number_of_infos: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_network_groups_infos".}
proc hailo_network_group_get_all_stream_infos*(
    network_group: hailo_configured_network_group;
    stream_infos: ptr hailo_stream_info_t; stream_infos_length: csize_t;
    number_of_streams: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_network_group_get_all_stream_infos".}
proc hailo_network_group_get_input_stream_infos*(
    network_group: hailo_configured_network_group;
    stream_infos: ptr hailo_stream_info_t; stream_infos_length: csize_t;
    number_of_streams: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_network_group_get_input_stream_infos".}
proc hailo_network_group_get_output_stream_infos*(
    network_group: hailo_configured_network_group;
    stream_infos: ptr hailo_stream_info_t; stream_infos_length: csize_t;
    number_of_streams: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_network_group_get_output_stream_infos".}
proc hailo_shutdown_network_group*(network_group: hailo_configured_network_group): hailo_status {.
    cdecl, importc: "hailo_shutdown_network_group".}
proc hailo_activate_network_group*(network_group: hailo_configured_network_group;
    activation_params: ptr hailo_activate_network_group_params_t;
    activated_network_group_out: ptr hailo_activated_network_group): hailo_status {.
    cdecl, importc: "hailo_activate_network_group".}
proc hailo_deactivate_network_group*(activated_network_group: hailo_activated_network_group): hailo_status {.
    cdecl, importc: "hailo_deactivate_network_group".}
proc hailo_get_input_stream*(configured_network_group: hailo_configured_network_group;
                             stream_name: cstring;
                             stream: ptr hailo_input_stream): hailo_status {.
    cdecl, importc: "hailo_get_input_stream".}
proc hailo_get_output_stream*(configured_network_group: hailo_configured_network_group;
                              stream_name: cstring;
                              stream: ptr hailo_output_stream): hailo_status {.
    cdecl, importc: "hailo_get_output_stream".}
proc hailo_get_latency_measurement*(configured_network_group: hailo_configured_network_group;
                                    network_name: cstring; result: ptr hailo_latency_measurement_result_t): hailo_status {.
    cdecl, importc: "hailo_get_latency_measurement".}
proc hailo_set_scheduler_timeout*(configured_network_group: hailo_configured_network_group;
                                  timeout_ms: uint32; network_name: cstring): hailo_status {.
    cdecl, importc: "hailo_set_scheduler_timeout".}
proc hailo_set_scheduler_threshold*(configured_network_group: hailo_configured_network_group;
                                    threshold: uint32; network_name: cstring): hailo_status {.
    cdecl, importc: "hailo_set_scheduler_threshold".}
proc hailo_set_scheduler_priority*(configured_network_group: hailo_configured_network_group;
                                   priority: uint8; network_name: cstring): hailo_status {.
    cdecl, importc: "hailo_set_scheduler_priority".}
proc hailo_allocate_buffer*(size: csize_t;
                            allocation_params: ptr hailo_buffer_parameters_t;
                            buffer_out: ptr pointer): hailo_status {.cdecl,
    importc: "hailo_allocate_buffer".}
proc hailo_free_buffer*(buffer: pointer): hailo_status {.cdecl,
    importc: "hailo_free_buffer".}
proc hailo_device_dma_map_buffer*(device: hailo_device; address: pointer;
                                  size: csize_t;
                                  direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_device_dma_map_buffer".}
proc hailo_device_dma_unmap_buffer*(device: hailo_device; address: pointer;
                                    size: csize_t;
                                    direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_device_dma_unmap_buffer".}
proc hailo_vdevice_dma_map_buffer*(vdevice: hailo_vdevice; address: pointer;
                                   size: csize_t;
                                   direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_vdevice_dma_map_buffer".}
proc hailo_vdevice_dma_unmap_buffer*(vdevice: hailo_vdevice; address: pointer;
                                     size: csize_t;
                                     direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_vdevice_dma_unmap_buffer".}
proc hailo_device_dma_map_dmabuf*(device: hailo_device; dmabuf_fd: cint;
                                  size: csize_t;
                                  direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_device_dma_map_dmabuf".}
proc hailo_device_dma_unmap_dmabuf*(device: hailo_device; dmabuf_fd: cint;
                                    size: csize_t;
                                    direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_device_dma_unmap_dmabuf".}
proc hailo_vdevice_dma_map_dmabuf*(vdevice: hailo_vdevice; dmabuf_fd: cint;
                                   size: csize_t;
                                   direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_vdevice_dma_map_dmabuf".}
proc hailo_vdevice_dma_unmap_dmabuf*(vdevice: hailo_vdevice; dmabuf_fd: cint;
                                     size: csize_t;
                                     direction: hailo_dma_buffer_direction_t): hailo_status {.
    cdecl, importc: "hailo_vdevice_dma_unmap_dmabuf".}
proc hailo_set_input_stream_timeout*(stream: hailo_input_stream;
                                     timeout_ms: uint32): hailo_status {.cdecl,
    importc: "hailo_set_input_stream_timeout".}
proc hailo_set_output_stream_timeout*(stream: hailo_output_stream;
                                      timeout_ms: uint32): hailo_status {.cdecl,
    importc: "hailo_set_output_stream_timeout".}
proc hailo_get_input_stream_frame_size*(stream: hailo_input_stream): csize_t {.
    cdecl, importc: "hailo_get_input_stream_frame_size".}
proc hailo_get_output_stream_frame_size*(stream: hailo_output_stream): csize_t {.
    cdecl, importc: "hailo_get_output_stream_frame_size".}
proc hailo_get_input_stream_info*(stream: hailo_input_stream;
                                  stream_info: ptr hailo_stream_info_t): hailo_status {.
    cdecl, importc: "hailo_get_input_stream_info".}
proc hailo_get_output_stream_info*(stream: hailo_output_stream;
                                   stream_info: ptr hailo_stream_info_t): hailo_status {.
    cdecl, importc: "hailo_get_output_stream_info".}
proc hailo_get_input_stream_quant_infos*(stream: hailo_input_stream;
    quant_infos: ptr hailo_quant_info_t; quant_infos_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_input_stream_quant_infos".}
proc hailo_get_output_stream_quant_infos*(stream: hailo_output_stream;
    quant_infos: ptr hailo_quant_info_t; quant_infos_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_output_stream_quant_infos".}
proc hailo_stream_read_raw_buffer*(stream: hailo_output_stream; buffer: pointer;
                                   size: csize_t): hailo_status {.cdecl,
    importc: "hailo_stream_read_raw_buffer".}
proc hailo_stream_write_raw_buffer*(stream: hailo_input_stream; buffer: pointer;
                                    size: csize_t): hailo_status {.cdecl,
    importc: "hailo_stream_write_raw_buffer".}
proc hailo_stream_wait_for_async_output_ready*(stream: hailo_output_stream;
    transfer_size: csize_t; timeout_ms: uint32): hailo_status {.cdecl,
    importc: "hailo_stream_wait_for_async_output_ready".}
proc hailo_stream_wait_for_async_input_ready*(stream: hailo_input_stream;
    transfer_size: csize_t; timeout_ms: uint32): hailo_status {.cdecl,
    importc: "hailo_stream_wait_for_async_input_ready".}
proc hailo_output_stream_get_async_max_queue_size*(stream: hailo_output_stream;
    queue_size: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_output_stream_get_async_max_queue_size".}
proc hailo_input_stream_get_async_max_queue_size*(stream: hailo_input_stream;
    queue_size: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_input_stream_get_async_max_queue_size".}
proc hailo_stream_read_raw_buffer_async*(stream: hailo_output_stream;
    buffer: pointer; size: csize_t;
    user_callback: hailo_stream_read_async_callback_t; opaque: pointer): hailo_status {.
    cdecl, importc: "hailo_stream_read_raw_buffer_async".}
proc hailo_stream_write_raw_buffer_async*(stream: hailo_input_stream;
    buffer: pointer; size: csize_t;
    user_callback: hailo_stream_write_async_callback_t; opaque: pointer): hailo_status {.
    cdecl, importc: "hailo_stream_write_raw_buffer_async".}
proc hailo_get_host_frame_size*(stream_info: ptr hailo_stream_info_t;
                                transform_params: ptr hailo_transform_params_t): csize_t {.
    cdecl, importc: "hailo_get_host_frame_size".}
proc hailo_create_input_transform_context*(stream_info: ptr hailo_stream_info_t;
    transform_params: ptr hailo_transform_params_t;
    transform_context: ptr hailo_input_transform_context): hailo_status {.cdecl,
    importc: "hailo_create_input_transform_context".}
proc hailo_create_input_transform_context_by_stream*(stream: hailo_input_stream;
    transform_params: ptr hailo_transform_params_t;
    transform_context: ptr hailo_input_transform_context): hailo_status {.cdecl,
    importc: "hailo_create_input_transform_context_by_stream".}
proc hailo_release_input_transform_context*(
    transform_context: hailo_input_transform_context): hailo_status {.cdecl,
    importc: "hailo_release_input_transform_context".}
proc hailo_is_input_transformation_required2*(
    src_image_shape: ptr hailo_3d_image_shape_t; src_format: ptr hailo_format_t;
    dst_image_shape: ptr hailo_3d_image_shape_t; dst_format: ptr hailo_format_t;
    quant_infos: ptr hailo_quant_info_t; quant_infos_count: csize_t;
    transformation_required: ptr bool): hailo_status {.cdecl,
    importc: "hailo_is_input_transformation_required2".}
proc hailo_transform_frame_by_input_transform_context*(
    transform_context: hailo_input_transform_context; src: pointer;
    src_size: csize_t; dst: pointer; dst_size: csize_t): hailo_status {.cdecl,
    importc: "hailo_transform_frame_by_input_transform_context".}
proc hailo_is_output_transformation_required2*(
    src_image_shape: ptr hailo_3d_image_shape_t; src_format: ptr hailo_format_t;
    dst_image_shape: ptr hailo_3d_image_shape_t; dst_format: ptr hailo_format_t;
    quant_infos: ptr hailo_quant_info_t; quant_infos_count: csize_t;
    transformation_required: ptr bool): hailo_status {.cdecl,
    importc: "hailo_is_output_transformation_required2".}
proc hailo_create_output_transform_context*(
    stream_info: ptr hailo_stream_info_t;
    transform_params: ptr hailo_transform_params_t;
    transform_context: ptr hailo_output_transform_context): hailo_status {.
    cdecl, importc: "hailo_create_output_transform_context".}
proc hailo_create_output_transform_context_by_stream*(
    stream: hailo_output_stream; transform_params: ptr hailo_transform_params_t;
    transform_context: ptr hailo_output_transform_context): hailo_status {.
    cdecl, importc: "hailo_create_output_transform_context_by_stream".}
proc hailo_release_output_transform_context*(
    transform_context: hailo_output_transform_context): hailo_status {.cdecl,
    importc: "hailo_release_output_transform_context".}
proc hailo_transform_frame_by_output_transform_context*(
    transform_context: hailo_output_transform_context; src: pointer;
    src_size: csize_t; dst: pointer; dst_size: csize_t): hailo_status {.cdecl,
    importc: "hailo_transform_frame_by_output_transform_context".}
proc hailo_is_qp_valid*(quant_info: hailo_quant_info_t; is_qp_valid: ptr bool): hailo_status {.
    cdecl, importc: "hailo_is_qp_valid".}
proc hailo_create_demuxer_by_stream*(stream: hailo_output_stream;
                                     demux_params: ptr hailo_demux_params_t;
                                     demuxer: ptr hailo_output_demuxer): hailo_status {.
    cdecl, importc: "hailo_create_demuxer_by_stream".}
proc hailo_release_output_demuxer*(demuxer: hailo_output_demuxer): hailo_status {.
    cdecl, importc: "hailo_release_output_demuxer".}
proc hailo_demux_raw_frame_by_output_demuxer*(demuxer: hailo_output_demuxer;
    src: pointer; src_size: csize_t; raw_buffers: ptr hailo_stream_raw_buffer_t;
    raw_buffers_count: csize_t): hailo_status {.cdecl,
    importc: "hailo_demux_raw_frame_by_output_demuxer".}
proc hailo_demux_by_name_raw_frame_by_output_demuxer*(
    demuxer: hailo_output_demuxer; src: pointer; src_size: csize_t;
    raw_buffers_by_name: ptr hailo_stream_raw_buffer_by_name_t;
    raw_buffers_count: csize_t): hailo_status {.cdecl,
    importc: "hailo_demux_by_name_raw_frame_by_output_demuxer".}
proc hailo_get_mux_infos_by_output_demuxer*(demuxer: hailo_output_demuxer;
    stream_infos: ptr hailo_stream_info_t; number_of_streams: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_mux_infos_by_output_demuxer".}
proc hailo_fuse_nms_frames*(nms_fuse_inputs: ptr hailo_nms_fuse_input_t;
                            inputs_count: uint32; fused_buffer: ptr uint8;
                            fused_buffer_size: csize_t): hailo_status {.cdecl,
    importc: "hailo_fuse_nms_frames".}
proc hailo_hef_make_input_vstream_params*(hef: hailo_hef; name: cstring;
    unused: bool; format_type: hailo_format_type_t;
    input_params: ptr hailo_input_vstream_params_by_name_t;
    input_params_count: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_hef_make_input_vstream_params".}
proc hailo_hef_make_output_vstream_params*(hef: hailo_hef; name: cstring;
    unused: bool; format_type: hailo_format_type_t;
    output_params: ptr hailo_output_vstream_params_by_name_t;
    output_params_count: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_hef_make_output_vstream_params".}
proc hailo_make_input_vstream_params*(network_group: hailo_configured_network_group;
                                      unused: bool;
                                      format_type: hailo_format_type_t;
    input_params: ptr hailo_input_vstream_params_by_name_t;
                                      input_params_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_make_input_vstream_params".}
proc hailo_make_output_vstream_params*(network_group: hailo_configured_network_group;
                                       unused: bool;
                                       format_type: hailo_format_type_t;
    output_params: ptr hailo_output_vstream_params_by_name_t;
                                       output_params_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_make_output_vstream_params".}
proc hailo_get_output_vstream_groups*(network_group: hailo_configured_network_group;
    output_name_by_group: ptr hailo_output_vstream_name_by_group_t;
                                      output_name_by_group_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_output_vstream_groups".}
proc hailo_create_input_vstreams*(configured_network_group: hailo_configured_network_group;
    inputs_params: ptr hailo_input_vstream_params_by_name_t;
                                  inputs_count: csize_t;
                                  input_vstreams: ptr hailo_input_vstream): hailo_status {.
    cdecl, importc: "hailo_create_input_vstreams".}
proc hailo_create_output_vstreams*(configured_network_group: hailo_configured_network_group;
    outputs_params: ptr hailo_output_vstream_params_by_name_t;
                                   outputs_count: csize_t;
                                   output_vstreams: ptr hailo_output_vstream): hailo_status {.
    cdecl, importc: "hailo_create_output_vstreams".}
proc hailo_get_input_vstream_frame_size*(input_vstream: hailo_input_vstream;
    frame_size: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_get_input_vstream_frame_size".}
proc hailo_get_input_vstream_info*(input_vstream: hailo_input_vstream;
                                   vstream_info: ptr hailo_vstream_info_t): hailo_status {.
    cdecl, importc: "hailo_get_input_vstream_info".}
proc hailo_get_input_vstream_user_format*(input_vstream: hailo_input_vstream;
    user_buffer_format: ptr hailo_format_t): hailo_status {.cdecl,
    importc: "hailo_get_input_vstream_user_format".}
proc hailo_get_input_vstream_quant_infos*(vstream: hailo_input_vstream;
    quant_infos: ptr hailo_quant_info_t; quant_infos_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_input_vstream_quant_infos".}
proc hailo_get_output_vstream_quant_infos*(vstream: hailo_output_vstream;
    quant_infos: ptr hailo_quant_info_t; quant_infos_count: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_output_vstream_quant_infos".}
proc hailo_get_output_vstream_frame_size*(output_vstream: hailo_output_vstream;
    frame_size: ptr csize_t): hailo_status {.cdecl,
    importc: "hailo_get_output_vstream_frame_size".}
proc hailo_get_output_vstream_info*(output_vstream: hailo_output_vstream;
                                    vstream_info: ptr hailo_vstream_info_t): hailo_status {.
    cdecl, importc: "hailo_get_output_vstream_info".}
proc hailo_get_output_vstream_user_format*(output_vstream: hailo_output_vstream;
    user_buffer_format: ptr hailo_format_t): hailo_status {.cdecl,
    importc: "hailo_get_output_vstream_user_format".}
proc hailo_get_vstream_frame_size*(vstream_info: ptr hailo_vstream_info_t;
                                   user_buffer_format: ptr hailo_format_t;
                                   frame_size: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_vstream_frame_size".}
proc hailo_vstream_write_raw_buffer*(input_vstream: hailo_input_vstream;
                                     buffer: pointer; buffer_size: csize_t): hailo_status {.
    cdecl, importc: "hailo_vstream_write_raw_buffer".}
proc hailo_vstream_write_pix_buffer*(input_vstream: hailo_input_vstream;
                                     buffer: ptr hailo_pix_buffer_t): hailo_status {.
    cdecl, importc: "hailo_vstream_write_pix_buffer".}
proc hailo_flush_input_vstream*(input_vstream: hailo_input_vstream): hailo_status {.
    cdecl, importc: "hailo_flush_input_vstream".}
proc hailo_vstream_read_raw_buffer*(output_vstream: hailo_output_vstream;
                                    buffer: pointer; buffer_size: csize_t): hailo_status {.
    cdecl, importc: "hailo_vstream_read_raw_buffer".}
proc hailo_vstream_set_nms_score_threshold*(
    output_vstream: hailo_output_vstream; threshold: float32_t): hailo_status {.
    cdecl, importc: "hailo_vstream_set_nms_score_threshold".}
proc hailo_vstream_set_nms_iou_threshold*(output_vstream: hailo_output_vstream;
    threshold: float32_t): hailo_status {.cdecl,
    importc: "hailo_vstream_set_nms_iou_threshold".}
proc hailo_vstream_set_nms_max_proposals_per_class*(
    output_vstream: hailo_output_vstream; max_proposals_per_class: uint32): hailo_status {.
    cdecl, importc: "hailo_vstream_set_nms_max_proposals_per_class".}
proc hailo_release_input_vstreams*(input_vstreams: ptr hailo_input_vstream;
                                   inputs_count: csize_t): hailo_status {.cdecl,
    importc: "hailo_release_input_vstreams".}
proc hailo_release_output_vstreams*(output_vstreams: ptr hailo_output_vstream;
                                    outputs_count: csize_t): hailo_status {.
    cdecl, importc: "hailo_release_output_vstreams".}
proc hailo_clear_input_vstreams*(input_vstreams: ptr hailo_input_vstream;
                                 inputs_count: csize_t): hailo_status {.cdecl,
    importc: "hailo_clear_input_vstreams".}
proc hailo_clear_output_vstreams*(output_vstreams: ptr hailo_output_vstream;
                                  outputs_count: csize_t): hailo_status {.cdecl,
    importc: "hailo_clear_output_vstreams".}
proc hailo_infer*(configured_network_group: hailo_configured_network_group;
                  inputs_params: ptr hailo_input_vstream_params_by_name_t;
                  input_buffers: ptr hailo_stream_raw_buffer_by_name_t;
                  inputs_count: csize_t;
                  outputs_params: ptr hailo_output_vstream_params_by_name_t;
                  output_buffers: ptr hailo_stream_raw_buffer_by_name_t;
                  outputs_count: csize_t; frames_count: csize_t): hailo_status {.
    cdecl, importc: "hailo_infer".}
proc hailo_hef_get_network_infos*(hef: hailo_hef; network_group_name: cstring;
                                  networks_infos: ptr hailo_network_info_t;
                                  number_of_networks: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_hef_get_network_infos".}
proc hailo_get_network_infos*(network_group: hailo_configured_network_group;
                              networks_infos: ptr hailo_network_info_t;
                              number_of_networks: ptr csize_t): hailo_status {.
    cdecl, importc: "hailo_get_network_infos".}
proc hailo_set_sleep_state*(device: hailo_device;
                            sleep_state: hailo_sleep_state_t): hailo_status {.
    cdecl, importc: "hailo_set_sleep_state".}
proc hailo_is_input_transformation_required*(
    src_image_shape: ptr hailo_3d_image_shape_t; src_format: ptr hailo_format_t;
    dst_image_shape: ptr hailo_3d_image_shape_t; dst_format: ptr hailo_format_t;
    quant_info: ptr hailo_quant_info_t; transformation_required: ptr bool): hailo_status {.
    cdecl, importc: "hailo_is_input_transformation_required".}
proc hailo_is_output_transformation_required*(
    src_image_shape: ptr hailo_3d_image_shape_t; src_format: ptr hailo_format_t;
    dst_image_shape: ptr hailo_3d_image_shape_t; dst_format: ptr hailo_format_t;
    quant_info: ptr hailo_quant_info_t; transformation_required: ptr bool): hailo_status {.
    cdecl, importc: "hailo_is_output_transformation_required".}