#ifndef PARAMETERS_H
#define PARAMETERS_H

// NO RS485/EXTRUDER CONTROLLER SUPPORT
// PLEASE VERIFY PIN ASSIGNMENTS FOR YOUR CONFIGURATION!!!!!!!
#define MOTHERBOARD 6 // ATMEGA168 = 0, SANGUINO = 1, MOTHERBOARD = 2, MEGA/RAMPS = 3, ATMEGA328 = 4, Gen6 = 5, Sanguinololu = 6

//Comment out to disable SD support
//#define SDSUPPORT 1

#define SLOW_XY 1500.0 // Feedrate from which the motors can do a standing start
#define FAST_XY 2500.0 // Fastest feedrate possible
#define SLOW_Z 50.0 // Feedrate from which the motors can do a standing start
#define FAST_Z 50.0 // Fastest feedrate possible

//PID settings:
//Uncomment the following line to enable PID support. This is untested and could be disastrous. Be careful.
//#define PIDTEMP 1
#ifdef PIDTEMP
#define PID_MAX 255 // limits current to nozzle
#define PID_INTEGRAL_DRIVE_MAX 220
#define PID_PGAIN 180 //100 is 1.0
#define PID_IGAIN 2 //100 is 1.0
#define PID_DGAIN 100 //100 is 1.0
#endif

//Experimental temperature smoothing - only uncomment this if your temp readings are noisy
//#define SMOOTHING 1
//#define SMOOTHFACTOR 16 //best to use a power of two here - determines how many values are averaged together by the smoothing algorithm

//Experimental watchdog and minimal temp
//The watchdog waits for the watchperiod in milliseconds whenever an M104 or M109 increases the target temperature
//If the temperature has not increased at the end of that period, the target temperature is set to zero. It can be reset with another M104/M109
//#define WATCHPERIOD 5000 //5 seconds
//The minimal temperature defines the temperature below which the heater will not be enabled
//#define MINTEMP 

// Select one of these only to define how the nozzle temp is read.
#define HEATER_USES_THERMISTOR

// Select one of these only to define how the bed temp is read.
#define BED_USES_THERMISTOR

// Calibration formulas
// e_extruded_steps_per_mm = e_feedstock_steps_per_mm * (desired_extrusion_diameter^2 / feedstock_diameter^2)
// new_axis_steps_per_mm = previous_axis_steps_per_mm * (test_distance_instructed/test_distance_traveled)
// units are in millimeters or whatever length unit you prefer: inches,football-fields,parsecs etc

//Calibration variables
//float x_steps_per_unit = 80;  // 8 tooth pulley, T5 belt
//float y_steps_per_unit = 80;  // 8 tooth pulley, T5 belt
float x_steps_per_unit = 91.4286;  // 14 tooth pulley, T2.5 belt
float y_steps_per_unit = 91.4286;  // 14 tooth pulley, T2.5 belt
float z_steps_per_unit = 2560;
float e_steps_per_unit = 30; // Should be 30
float f_steps_per_unit = 1;

//float max_feedrate = 12000;

//For Inverting Stepper Enable Pins (Active Low) use 0, Non Inverting (Active High) use 1
const bool X_ENABLE_ON = 0;
const bool Y_ENABLE_ON = 0;
const bool Z_ENABLE_ON = 0;
const bool E_ENABLE_ON = 0;

//Disables axis when it's not being used.
const bool DISABLE_X = false;
const bool DISABLE_Y = false;
const bool DISABLE_Z = false;
const bool DISABLE_E = false;

const bool INVERT_X_DIR = false;
const bool INVERT_Y_DIR = false;
const bool INVERT_Z_DIR = false;
const bool INVERT_E_DIR = false;

//Thermistor settings:
//Uncomment for 10k thermistor
#include "BedThermistorTable_10k_EPCOS_B57550G103J.h"

//Thermistor settings:
//Uncomment for 100k thermistor
#include "ThermistorTable_100k_EPCOS_B57540G0104J.h"

//Endstop Settings
#define ENDSTOPPULLUPS 1
const bool ENDSTOPS_INVERTING = false;
const bool min_software_endstops = false; //If true, axis won't move to coordinates less than zero.  N.B. If true this prevents G28 homing axes.
const bool max_software_endstops = true;  //If true, axis won't move to coordinates greater than the defined lengths below.
const int X_MAX_LENGTH = 220;
const int Y_MAX_LENGTH = 220;
const int Z_MAX_LENGTH = 100;

#define BAUDRATE 115200



#endif
