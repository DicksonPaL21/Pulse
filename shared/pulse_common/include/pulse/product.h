/* Product name and version of PulseService, in one place for the C++ code
 * (constants.hpp, version.hpp) and for PulseService.rc, which can only read
 * preprocessor definitions. Plain C on purpose: the resource compiler reads
 * .h files for their #defines only. */
#ifndef PULSE_PRODUCT_H_
#define PULSE_PRODUCT_H_

#define PULSE_PRODUCT_NAME "Pulse Diagnostics"
#define PULSE_SERVICE_DISPLAY_NAME "Pulse Diagnostics Service"

#define PULSE_VERSION_MAJOR 1
#define PULSE_VERSION_MINOR 6
#define PULSE_VERSION_PATCH 0
#define PULSE_VERSION_STRING "1.6.0"

#endif /* PULSE_PRODUCT_H_ */
