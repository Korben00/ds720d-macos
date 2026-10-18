// SPDX-License-Identifier: MIT
// The SANE dynamic loader resolves backend-prefixed entry points.
#define sane_init sane_ds720d_init
#define sane_exit sane_ds720d_exit
#define sane_get_devices sane_ds720d_get_devices
#define sane_open sane_ds720d_open
#define sane_close sane_ds720d_close
#define sane_get_option_descriptor sane_ds720d_get_option_descriptor
#define sane_control_option sane_ds720d_control_option
#define sane_get_parameters sane_ds720d_get_parameters
#define sane_start sane_ds720d_start
#define sane_read sane_ds720d_read
#define sane_cancel sane_ds720d_cancel
#define sane_set_io_mode sane_ds720d_set_io_mode
#define sane_get_select_fd sane_ds720d_get_select_fd
