// Sprinter RepRap firmware rewrite based onf Hydra-mmm firmware.
// Licence: GPL

// Extensively modified by Adrian; 29 September 2011

#include "fastio.h"
#include "Configuration.h"
#include "pins.h"
#include "Sprinter.h"

#ifdef SDSUPPORT
#include "SdFat.h"
#endif

// look here for descriptions of gcodes: http://reprap.org/wiki/GCodes


//Stepper Movement Variables

boolean check_endstops = false;

boolean ok_sent = false;

char axis_codes[NUM_AXIS] = {'X', 'Y', 'Z', 'E'};
bool move_direction[NUM_AXIS];
unsigned long axis_previous_micros[NUM_AXIS];
unsigned long previous_micros = 0, previous_millis_heater, previous_millis_bed_heater;
unsigned long move_steps_to_take[NUM_AXIS];
float current_feedrate = 100.0;
#ifdef RAMP_ACCELERATION
unsigned long axis_max_interval[NUM_AXIS];
unsigned long axis_steps_per_sqr_second[NUM_AXIS];
unsigned long axis_travel_steps_per_sqr_second[NUM_AXIS];
unsigned long max_interval;
unsigned long steps_per_sqr_second, plateau_steps;  
#endif
boolean acceleration_enabled = false, accelerating = false;
unsigned long interval;
float destination[NUM_AXIS] = {0.0, 0.0, 0.0, 0.0};
float current_position[NUM_AXIS] = {0.0, 0.0, 0.0, 0.0};
unsigned long steps_taken[NUM_AXIS];
long axis_interval[NUM_AXIS]; // for speed delay
bool home_all_axis = true;
int destination_feedrate = 1500, next_feedrate, saved_feedrate;
float time_for_move;
long gcode_N, gcode_LastN;
bool relative_mode = false;  //Determines Absolute or Relative Coordinates
bool relative_mode_e = false;  //Determines Absolute or Relative E Codes while in Absolute Coordinates mode. E is always relative in Relative Coordinates mode.
long timediff = 0;
//experimental feedrate calc
float d = 0;
float axis_diff[NUM_AXIS] = {0, 0, 0, 0};
#ifdef STEP_DELAY_RATIO
long long_step_delay_ratio = STEP_DELAY_RATIO * 100;
#endif


// comm variables
#define MAX_CMD_SIZE 96
#define BUFSIZE 8
char cmdbuffer[BUFSIZE][MAX_CMD_SIZE];
bool fromsd[BUFSIZE];
int bufindr = 0;
int bufindw = 0;
int buflen = 0;
int i = 0;
char serial_char;
int serial_count = 0;
boolean comment_mode = false;
char *strchr_pointer; // just a pointer to find chars in the cmd string like X, Y, Z, E, etc

// Manage heater variables. For a thermistor or AD595 thermocouple, raw values refer to the 
// reading from the analog pin. For a MAX6675 thermocouple, the raw value is the temperature in 0.25 
// degree increments (i.e. 100=25 deg). 

int target_raw = 0;
int current_raw = 0;
int target_bed_raw = 0;
int current_bed_raw = 0;
int tt = 0, bt = 0;
#ifdef PIDTEMP
int temp_iState = 0;
int temp_dState = 0;
int pTerm;
int iTerm;
int dTerm;
//int output;
int error;
int temp_iState_min = 100 * -PID_INTEGRAL_DRIVE_MAX / PID_IGAIN;
int temp_iState_max = 100 * PID_INTEGRAL_DRIVE_MAX / PID_IGAIN;
#endif
#ifdef SMOOTHING
uint32_t nma = 0;
#endif
#ifdef WATCHPERIOD
int watch_raw = -1000;
unsigned long watchmillis = 0;
#endif
#ifdef MINTEMP
int minttemp = temp2analogh(MINTEMP);
#endif
#ifdef MAXTEMP
int maxttemp = temp2analogh(MAXTEMP);
#endif

//Inactivity shutdown variables
unsigned long previous_millis_cmd = 0;
unsigned long max_inactive_time = 0;
unsigned long stepper_inactive_time = 0;

#ifdef SDSUPPORT
Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;
uint32_t filesize = 0;
uint32_t sdpos = 0;
bool sdmode = false;
bool sdactive = false;
bool savetosd = false;
int16_t n;

void initsd(){
	sdactive = false;
	#if SDSS >- 1
	if(root.isOpen())
		root.close();
	if (!card.init(SPI_FULL_SPEED,SDSS)){
		//if (!card.init(SPI_HALF_SPEED,SDSS))
		Serial.println("// SD init fail");
	}
	else if (!volume.init(&card))
		Serial.println("// Volume.init failed");
	else if (!root.openRoot(&volume)) 
		Serial.println("// OpenRoot failed");
	else 
        {
                Serial.println("// SD card is active");
		sdactive = true;
        }
	#endif
}

inline void write_command(char *buf){
	char* begin = buf;
	char* npos = 0;
	char* end = buf + strlen(buf) - 1;

	file.writeError = false;
	if((npos = strchr(buf, 'N')) != NULL){
		begin = strchr(npos, ' ') + 1;
		end = strchr(npos, '*') - 1;
	}
	end[1] = '\r';
	end[2] = '\n';
	end[3] = '\0';
	//Serial.println(begin);
	file.write(begin);
	if (file.writeError){
		Serial.println("// error writing to file");
	}
}
#endif


void setup()
{ 
	Serial.begin(BAUDRATE);
	Serial.println("start");
	for(int i = 0; i < BUFSIZE; i++){
		fromsd[i] = false;
	}


	//Initialize Dir Pins
	#if X_DIR_PIN > -1
	SET_OUTPUT(X_DIR_PIN);
	#endif
	#if Y_DIR_PIN > -1 
	SET_OUTPUT(Y_DIR_PIN);
	#endif
	#if Z_DIR_PIN > -1 
	SET_OUTPUT(Z_DIR_PIN);
	#endif
	#if E_DIR_PIN > -1 
	SET_OUTPUT(E_DIR_PIN);
	#endif

	//Initialize Enable Pins - steppers default to disabled.

	#if (X_ENABLE_PIN > -1)
		SET_OUTPUT(X_ENABLE_PIN);
	if(!X_ENABLE_ON) WRITE(X_ENABLE_PIN,HIGH);
	#endif
	#if (Y_ENABLE_PIN > -1)
		SET_OUTPUT(Y_ENABLE_PIN);
	if(!Y_ENABLE_ON) WRITE(Y_ENABLE_PIN,HIGH);
	#endif
	#if (Z_ENABLE_PIN > -1)
		SET_OUTPUT(Z_ENABLE_PIN);
	if(!Z_ENABLE_ON) WRITE(Z_ENABLE_PIN,HIGH);
	#endif
	#if (E_ENABLE_PIN > -1)
		SET_OUTPUT(E_ENABLE_PIN);
	if(!E_ENABLE_ON) WRITE(E_ENABLE_PIN,HIGH);
	#endif

	//endstops and pullups
	#ifdef ENDSTOPPULLUPS
	#if X_MIN_PIN > -1
	SET_INPUT(X_MIN_PIN); 
	WRITE(X_MIN_PIN,HIGH);
	#endif
	#if X_MAX_PIN > -1
	SET_INPUT(X_MAX_PIN); 
	WRITE(X_MAX_PIN,HIGH);
	#endif
	#if Y_MIN_PIN > -1
	SET_INPUT(Y_MIN_PIN); 
	WRITE(Y_MIN_PIN,HIGH);
	#endif
	#if Y_MAX_PIN > -1
	SET_INPUT(Y_MAX_PIN); 
	WRITE(Y_MAX_PIN,HIGH);
	#endif
	#if Z_MIN_PIN > -1
	SET_INPUT(Z_MIN_PIN); 
	WRITE(Z_MIN_PIN,HIGH);
	#endif
	#if Z_MAX_PIN > -1
	SET_INPUT(Z_MAX_PIN); 
	WRITE(Z_MAX_PIN,HIGH);
	#endif
	#else
		#if X_MIN_PIN > -1
		SET_INPUT(X_MIN_PIN); 
		#endif
		#if X_MAX_PIN > -1
		SET_INPUT(X_MAX_PIN); 
		#endif
		#if Y_MIN_PIN > -1
		SET_INPUT(Y_MIN_PIN); 
		#endif
		#if Y_MAX_PIN > -1
		SET_INPUT(Y_MAX_PIN); 
		#endif
		#if Z_MIN_PIN > -1
		SET_INPUT(Z_MIN_PIN); 
		#endif
		#if Z_MAX_PIN > -1
		SET_INPUT(Z_MAX_PIN); 
		#endif
		#endif

		#if (HEATER_0_PIN > -1) 
			SET_OUTPUT(HEATER_0_PIN);
		#endif  
		#if (HEATER_1_PIN > -1) 
			SET_OUTPUT(HEATER_1_PIN);
		#endif  

		//Initialize Fan Pin
		#if (FAN_PIN > -1) 
			SET_OUTPUT(FAN_PIN);
		#endif

		//Initialize Step Pins
		#if (X_STEP_PIN > -1) 
			SET_OUTPUT(X_STEP_PIN);
		#endif  
		#if (Y_STEP_PIN > -1) 
			SET_OUTPUT(Y_STEP_PIN);
		#endif  
		#if (Z_STEP_PIN > -1) 
			SET_OUTPUT(Z_STEP_PIN);
		#endif  
		#if (E_STEP_PIN > -1) 
			SET_OUTPUT(E_STEP_PIN);
		#endif  
		#ifdef RAMP_ACCELERATION
		for(int i=0; i < NUM_AXIS; i++){
			axis_max_interval[i] = 100000000.0 / (max_start_speed_units_per_second[i] * axis_steps_per_unit[i]);
			axis_steps_per_sqr_second[i] = max_acceleration_units_per_sq_second[i] * axis_steps_per_unit[i];
			axis_travel_steps_per_sqr_second[i] = max_travel_acceleration_units_per_sq_second[i] * axis_steps_per_unit[i];
		}
		#endif

		#ifdef HEATER_USES_MAX6675
		SET_OUTPUT(SCK_PIN);
		WRITE(SCK_PIN,0);

		SET_OUTPUT(MOSI_PIN);
		WRITE(MOSI_PIN,1);

		SET_INPUT(MISO_PIN);
		WRITE(MISO_PIN,1);

		SET_OUTPUT(MAX6675_SS);
		WRITE(MAX6675_SS,1);
		#endif  

		#ifdef SDSUPPORT

		//power to SD reader
		#if SDPOWER > -1
		SET_OUTPUT(SDPOWER); 
		WRITE(SDPOWER,HIGH);
		#endif
		initsd();

		#endif

}


void loop()
{
	if(buflen<3)
		get_command();

	if(buflen){
		#ifdef SDSUPPORT
		if(savetosd){
			if(strstr(cmdbuffer[bufindr],"M29") == NULL){
				write_command(cmdbuffer[bufindr]);
                                ok_sent = true;
				Serial.println("ok");
			}else{
				file.sync();
				file.close();
				savetosd = false;
				Serial.println("// Done saving file.");
			}
		}else{
			process_commands();
		}
		#else
			process_commands();
		#endif
		buflen = (buflen-1);
		bufindr = (bufindr + 1)%BUFSIZE;
	}
	//check heater every n milliseconds
	manage_heater();
	manage_inactivity(1);
}


inline void get_command() 
{ 
	while( Serial.available() > 0  && buflen < BUFSIZE) 
	{
		serial_char = Serial.read() & 0x7F ; // Just to be sure
		if(serial_char == '\n' || serial_char == '\r' || serial_char == ':' || serial_count >= (MAX_CMD_SIZE - 1) ) 
		{
			if(!serial_count) 
			{
				comment_mode = false;
				return; //if empty line
			}
			cmdbuffer[bufindw][serial_count] = 0; //terminate string
			//if(!comment_mode)
			//{
				fromsd[bufindw] = false;
				if(strstr(cmdbuffer[bufindw], "N") != NULL)
				{
					strchr_pointer = strchr(cmdbuffer[bufindw], 'N');
					gcode_N = (strtol(&cmdbuffer[bufindw][strchr_pointer - cmdbuffer[bufindw] + 1], NULL, 10));
					if(gcode_N != gcode_LastN+1 && (strstr(cmdbuffer[bufindw], "M110") == NULL) ) 
					{
						Serial.print("// Serial Error: Line Number is not Last Line Number+1, Last Line:");
						Serial.println(gcode_LastN);
						//Serial.println(gcode_N);
						FlushSerialRequestResend();
						serial_count = 0;
						comment_mode = false;
						return;
					}

					if(strstr(cmdbuffer[bufindw], "*") != NULL)
					{
						byte checksum = 0;
						byte count = 0;
						while(cmdbuffer[bufindw][count] != '*') checksum = checksum^cmdbuffer[bufindw][count++];
						strchr_pointer = strchr(cmdbuffer[bufindw], '*');

						if( (int)(strtod(&cmdbuffer[bufindw][strchr_pointer - cmdbuffer[bufindw] + 1], NULL)) != checksum) 
						{
							Serial.print("// Error: checksum mismatch, Last Line:");
							Serial.println(gcode_LastN);
							FlushSerialRequestResend();
							serial_count = 0;
							comment_mode = false;
							return;
						}
						//if no errors, continue parsing
					}
					else 
					{
						Serial.print("// Error: No Checksum with line number, Last Line:");
						Serial.println(gcode_LastN);
						FlushSerialRequestResend();
						serial_count = 0;
						comment_mode = false;
						return;
					}

					gcode_LastN = gcode_N;
					//if no errors, continue parsing
				}
				else  // if we don't receive 'N' but still see '*'
				{
					if((strstr(cmdbuffer[bufindw], "*") != NULL))
					{
						Serial.print("// Error: No Line Number with checksum, Last Line:");
						Serial.println(gcode_LastN);
						serial_count = 0;
						comment_mode = false;
						return;
					}
				}
				if((strstr(cmdbuffer[bufindw], "G") != NULL))
				{
					strchr_pointer = strchr(cmdbuffer[bufindw], 'G');
					switch((int)((strtod(&cmdbuffer[bufindw][strchr_pointer - cmdbuffer[bufindw] + 1], NULL))))
					{
					case 0:
					case 1:
						#ifdef SDSUPPORT
						if(savetosd)
							break;
						#endif
                                                ok_sent = true;
						Serial.println("ok"); 
						break;
					default:
						break;
					}

				}
                                //Serial.println();
                                //Serial.println(cmdbuffer[bufindw]);
				bufindw = (bufindw + 1)%BUFSIZE;
				buflen += 1;

			//}
			comment_mode = false; //for new command
			serial_count = 0; //clear buffer

		}
		else
		{
                        if(serial_char == ';') comment_mode = true;
			if(!comment_mode) cmdbuffer[bufindw][serial_count++] = serial_char;
		}
	}
#ifdef SDSUPPORT
	if(!sdmode || serial_count!=0)
	{
		//comment_mode = false;
		return;
	}
	while( filesize > sdpos  && buflen < BUFSIZE) 
	{
		n = file.read();
		serial_char = (char)n & 0x7F; // Just to be sure
		if(serial_char == '\n' || serial_char == '\r' || serial_char == ':' || serial_count >= (MAX_CMD_SIZE - 1) || n == -1) 
		{
			sdpos = file.curPosition();
			if(sdpos >= filesize)
			{
				sdmode = false;
				Serial.println("// Done printing file");
			}
			if(!serial_count) 
			{
				comment_mode = false;
				return; //if empty line
			}
			cmdbuffer[bufindw][serial_count] = 0; //terminate string
			//if(!comment_mode)
			//{
				fromsd[bufindw] = true;
				buflen += 1;
				bufindw = (bufindw + 1)%BUFSIZE;
			//}
			comment_mode = false; //for new command
			serial_count = 0; //clear buffer
		}
		else
		{
			if(serial_char == ';') comment_mode = true;
			if(!comment_mode) cmdbuffer[bufindw][serial_count++] = serial_char;
		}
	}
#endif

}



inline float code_value() { return (strtod(&cmdbuffer[bufindr][strchr_pointer - cmdbuffer[bufindr] + 1], NULL)); }
inline long code_value_long() { return (strtol(&cmdbuffer[bufindr][strchr_pointer - cmdbuffer[bufindr] + 1], NULL, 10)); }
inline bool code_seen(char code_string[]) { return (strstr(cmdbuffer[bufindr], code_string) != NULL); }  //Return True if the string was found

inline bool code_seen(char code)
{
	strchr_pointer = strchr(cmdbuffer[bufindr], code);
	return (strchr_pointer != NULL);  //Return True if a character was found
}

inline void current_to_dest()
{
	destination[0] = current_position[0];
	destination[1] = current_position[1];
	destination[2] = current_position[2];
	destination[3] = current_position[3];
	destination_feedrate = current_feedrate;
}

void home_axis(float& destination, float& current, const float& slow, const float& fast, const float& max_length, const int min_pin)
{
        check_endstops = true;
  	saved_feedrate = current_feedrate;
  
  	current_feedrate = slow;
  	current_to_dest();
        destination = current - 2.0;
        destination_feedrate = fast;
        execute_move();
        
        if(min_pin >= 0)
  	  destination = -2.0*max_length;
        else
          destination = 0.0; // Best we can do
  	execute_move();
  
        if(min_pin < 0)
        {
          current_feedrate = saved_feedrate;
          return;
        }

  	current_feedrate = 0.25*slow;
  	current_to_dest();  
        destination = 1.0;
        execute_move();
  
        if(min_pin >= 0)
  	  destination = -10.0;
        else
          destination = 0.0; // Again, best we can do
        execute_move();
  
  	current = 0;
  	current_feedrate = saved_feedrate;
        check_endstops = false;
}

inline void process_commands()
{
	unsigned long codenum; //throw away variable
	char *starpos = NULL;
        boolean home_done = false;
        
	if(code_seen('G'))
	{
		switch((int)code_value())
		{
		case 0: // G0 -> G1
		case 1: // G1
			#if (defined DISABLE_CHECK_DURING_ACC) || (defined DISABLE_CHECK_DURING_MOVE) || (defined DISABLE_CHECK_DURING_TRAVEL)
			manage_heater();
			#endif
			get_coordinates(); // For X Y Z E F
			execute_move();
			previous_millis_cmd = millis();
			//ClearToSend();
			//return;
                        ok_sent = true; // Was done when the G1 was initially received.
			break;
		case 4: // G4 dwell
			codenum = 0;
			if(code_seen('P')) codenum = code_value(); // milliseconds to wait
			if(code_seen('S')) codenum = code_value() * 1000; // seconds to wait
			codenum += millis();  // keep track of when we started waiting
			while(millis()  < codenum ){
				manage_heater();
			}
			break;
                case 20:
                        Serial.println("// G20 - inches not supported.");
                        break;
                case 21:  // Metric - do nothing
                        break;
		case 28: //G28 Home axes
                        home_done = false;
                	if(code_seen(axis_codes[0]))
    	                {
                	  home_axis(destination[0], current_position[0], SLOW_XY, FAST_XY, X_MAX_LENGTH, X_MIN_PIN);
                	  home_done = true;
    	                }
    	                if(code_seen(axis_codes[1]))
    	                {
    	                  home_axis(destination[1], current_position[1], SLOW_XY, FAST_XY, Y_MAX_LENGTH, Y_MIN_PIN);
    	                  home_done = true;
    	                }
    	                if(code_seen(axis_codes[2]))
    	                {
    	                  home_axis(destination[2], current_position[2], SLOW_Z, FAST_Z, Z_MAX_LENGTH, Z_MIN_PIN);
    	                  home_done = true;
    	                }
    	                if(!home_done)
    	                {
    	                  home_axis(destination[0], current_position[0], SLOW_XY, FAST_XY, X_MAX_LENGTH, X_MIN_PIN);
    	                  home_axis(destination[1], current_position[1], SLOW_XY, FAST_XY, Y_MAX_LENGTH, Y_MIN_PIN);
    	                  home_axis(destination[2], current_position[2], SLOW_Z, FAST_Z, Z_MAX_LENGTH, Z_MIN_PIN);
    	                }
			previous_millis_cmd = millis();
			break;
		case 90: // G90
			relative_mode = false;
			break;
		case 91: // G91
			relative_mode = true;
			break;
		case 92: // G92
			for(int i=0; i < NUM_AXIS; i++) {
				if(code_seen(axis_codes[i])) current_position[i] = code_value();  
			}
			break;
                default:
                        Serial.print("// Unknown command: ");
                        Serial.println(cmdbuffer[bufindr]);

		}
	}

	else if(code_seen('M'))
	{

		switch( (int)code_value() ) 
		{
                case 0: kill();
                        break;
		#ifdef SDSUPPORT

		case 20: // M20 - list SD card
			Serial.print("ok Files: {");
			root.ls();
			Serial.println("}");
                        ok_sent = true;
			break;
		case 21: // M21 - init SD card
			sdmode = false;
			initsd();
			break;
		case 22: //M22 - release SD card
			sdmode = false;
			sdactive = false;
			break;
		case 23: //M23 - Select file
			if(sdactive){
				sdmode = false;
				file.close();
				starpos = (strchr(strchr_pointer + 4,'*'));
				if(starpos!=NULL)
					*(starpos-1)='\0';
				if (file.open(&root, strchr_pointer + 4, O_READ)) {
					Serial.print("// File opened:");
					Serial.print(strchr_pointer + 4);
					Serial.print("// Size:");
					Serial.println(file.fileSize());
					sdpos = 0;
					filesize = file.fileSize();
					Serial.println("// File selected");
				}
				else{
					Serial.println("ok File.open failed");
                                        ok_sent = true;
				}
			}
			break;
		case 24: //M24 - Start SD print
			if(sdactive){
				sdmode = true;
			}
			break;
		case 25: //M25 - Pause SD print
			if(sdmode){
				sdmode = false;
			}
			break;
		case 26: //M26 - Set SD index
			if(sdactive && code_seen('S')){
				sdpos = code_value_long();
				file.seekSet(sdpos);
			}
			break;
		case 27: //M27 - Get SD status
			if(sdactive){
				Serial.print("ok SD printing byte ");
				Serial.print(sdpos);
				Serial.print("/");
				Serial.println(filesize);
			}else{
				Serial.println("ok Not SD printing");
			}
                        ok_sent = true;
			break;
		case 28: //M28 - Start SD write
			if(sdactive){
				char* npos = 0;
				file.close();
				sdmode = false;
				starpos = (strchr(strchr_pointer + 4,'*'));
				if(starpos != NULL){
					npos = strchr(cmdbuffer[bufindr], 'N');
					strchr_pointer = strchr(npos,' ') + 1;
					*(starpos-1) = '\0';
				}
				if (!file.open(&root, strchr_pointer+4, O_CREAT | O_APPEND | O_WRITE | O_TRUNC))
				{
					Serial.print("// Open failed, File: ");
					Serial.print(strchr_pointer + 4);
					Serial.println(".");
				}else{
					savetosd = true;
					Serial.print("// Writing to file: ");
					Serial.println(strchr_pointer + 4);
				}
			}
			break;
		case 29: //M29 - Stop SD write
			//processed in write to file routine above
			//savetosd = false;
			break;
			#endif

         #if (PS_ON_PIN > -1)
		case 80: // M81 - ATX Power On
			SET_OUTPUT(PS_ON_PIN); //GND
			break;
		case 81: // M81 - ATX Power Off
			SET_INPUT(PS_ON_PIN); //Floating
			break;
	#endif

		case 82:
			axis_relative_modes[3] = false;
			break;
		case 83:
			axis_relative_modes[3] = true;
			break;
		case 84:
			if(code_seen('S')){ stepper_inactive_time = code_value() * 1000; }
			else{ disable_x(); disable_y(); disable_z(); disable_e(); }
			break;
		case 85: // M85
			code_seen('S');
			max_inactive_time = code_value() * 1000; 
			break;
		case 92: // M92
			for(int i=0; i < NUM_AXIS; i++) {
				if(code_seen(axis_codes[i])) axis_steps_per_unit[i] = code_value();
			}

			//Update start speed intervals and axis order. TODO: refactor axis_max_interval[] calculation into a function, as it
			// should also be used in setup() as well
			#ifdef RAMP_ACCELERATION
			long temp_max_intervals[NUM_AXIS];
			for(int i=0; i < NUM_AXIS; i++) {
				axis_max_interval[i] = 100000000.0 / (max_start_speed_units_per_second[i] * axis_steps_per_unit[i]);//TODO: do this for
				// all steps_per_unit related variables
			}
			#endif
			break;
                case 101: // Extruder forward - legacy
                        break;
                case 102: // Extruder reverse - legacy
                        break;
                case 103: // Extruder off - legacy
                        break;
		case 104: // M104
			if (code_seen('S')) target_raw = temp2analogh(code_value());
			#ifdef WATCHPERIOD
			if(target_raw > current_raw){
				watchmillis = max(1,millis());
				watch_raw = current_raw;
			}else{
				watchmillis = 0;
			}
			#endif
			break;



		case 105: // M105
			#if (TEMP_0_PIN > -1) || defined (HEATER_USES_MAX6675)|| defined HEATER_USES_AD595
			 tt = analog2temp(current_raw);
			#else
                         tt = -300; // Lower than absolute zero flags temperature unavailable
                        #endif
			#if TEMP_1_PIN > -1 || defined BED_USES_AD595
			 bt = analog2tempBed(current_bed_raw);
			#else
                         bt = -300;
                        #endif
			
                        ok_sent = true;
			Serial.print("ok T:");
			Serial.print(tt); 
			
			Serial.print(" B:");
			Serial.println(bt); 
			
			break;

	#if FAN_PIN > -1
		case 106: //M106 Fan On
			if (code_seen('S')){
				WRITE(FAN_PIN, HIGH);
				analogWrite(FAN_PIN, constrain(code_value(),0,255) );
			}
			else {
				WRITE(FAN_PIN, HIGH);
				analogWrite(FAN_PIN, 255 );
			}
			break;
		case 107: //M107 Fan Off
			analogWrite(FAN_PIN, 0);
			WRITE(FAN_PIN, LOW);
			break;
	#endif
			
                case 108: // Set extruder speed - legacy
                        break;
		case 109: // M109 - Wait for extruder heater to reach target.
			if (code_seen('S')) target_raw = temp2analogh(code_value());
			#ifdef WATCHPERIOD
			if(target_raw>current_raw){
				watchmillis = max(1,millis());
				watch_raw = current_raw;
			}else{
				watchmillis = 0;
			}
			#endif
			codenum = millis(); 
			while(current_raw < target_raw) {
				if( (millis() - codenum) > 1000 ) //Print Temp Reading every 1 second while heating up.
				{
					Serial.print("// T:");
					Serial.println( analog2temp(current_raw) ); 
					codenum = millis(); 
				}
				manage_heater();
			}
			break;
                case 110: // Set line number - dealt with by get_command() above
                        break;
                case 113: // Extruder PWM - legacy
                        break;
                case 114: // M114
                        ok_sent = true;
	                Serial.print("ok C:");
                        for(int i = 0; i < NUM_AXIS; i++)
                        {
                          Serial.print(" ");
                          Serial.print(axis_codes[i]);
                          Serial.print(":"); 
                          Serial.print(current_position[i]);
                        }
                        Serial.println();
                        break;

		case 115: // M115
			Serial.print("ok FIRMWARE_NAME:Sprinter FIRMWARE_URL:http%%3A/github.com/AdrianBowyer/RepRapLtd-engineering PROTOCOL_VERSION:1.X MACHINE_TYPE:Mendel EXTRUDER_COUNT:1 UUID:");
			Serial.println(uuid);
                        ok_sent = true;
			break;
                case 116: // TODO - wait for all temperatures
                        break;
                case 117: // TODO - report zero errors
                        break;
		case 119: // M119
                        Serial.print("// ");
			#if (X_MIN_PIN > -1)
				Serial.print("x_min:");
			Serial.print((READ(X_MIN_PIN)^ENDSTOPS_INVERTING)?"H ":"L ");
			#endif
			#if (X_MAX_PIN > -1)
				Serial.print("x_max:");
			Serial.print((READ(X_MAX_PIN)^ENDSTOPS_INVERTING)?"H ":"L ");
			#endif
			#if (Y_MIN_PIN > -1)
				Serial.print("y_min:");
			Serial.print((READ(Y_MIN_PIN)^ENDSTOPS_INVERTING)?"H ":"L ");
			#endif
			#if (Y_MAX_PIN > -1)
				Serial.print("y_max:");
			Serial.print((READ(Y_MAX_PIN)^ENDSTOPS_INVERTING)?"H ":"L ");
			#endif
			#if (Z_MIN_PIN > -1)
				Serial.print("z_min:");
			Serial.print((READ(Z_MIN_PIN)^ENDSTOPS_INVERTING)?"H ":"L ");
			#endif
			#if (Z_MAX_PIN > -1)
				Serial.print("z_max:");
			Serial.print((READ(Z_MAX_PIN)^ENDSTOPS_INVERTING)?"H ":"L ");
			#endif
			Serial.println();
			break;
			#ifdef RAMP_ACCELERATION
			//TODO: update for all axis, use for loop

                case 126: // TODO - open valve
                        break;
                case 127: // TODO - close valve
                        break;
		case 140: // M140 set bed temp
			#if TEMP_1_PIN > -1 || defined BED_USES_AD595
			if (code_seen('S')) target_bed_raw = temp2analogBed(code_value());
			#endif
			break;
		case 190: // M190 - Wait bed for heater to reach target.
			#if TEMP_1_PIN > -1
			if (code_seen('S')) target_bed_raw = temp2analogh(code_value());
			codenum = millis(); 
			while(current_bed_raw < target_bed_raw) {
				if( (millis()-codenum) > 1000 ) //Print Temp Reading every 1 second while heating up.
				{
					tt=analog2temp(current_raw);
					Serial.print("// T:");
					Serial.print( tt );
					Serial.print(" B:");
					Serial.println( analog2temp(current_bed_raw) ); 
					codenum = millis(); 
				}
				manage_heater();
			}
			#endif
			break;
		case 201: // M201
			for(int i=0; i < NUM_AXIS; i++) {
				if(code_seen(axis_codes[i])) axis_steps_per_sqr_second[i] = code_value() * axis_steps_per_unit[i];
			}
			break;
		case 202: // M202
			for(int i=0; i < NUM_AXIS; i++) {
				if(code_seen(axis_codes[i])) axis_travel_steps_per_sqr_second[i] = code_value() * axis_steps_per_unit[i];
			}
			break;
			#endif
                default:
                        Serial.print("// Unknown command: ");
                        Serial.println(cmdbuffer[bufindr]);

		}

	} else if (code_seen('T'))
        {
          // TODO Put some tool change code in here...
	}else{
                if(cmdbuffer[bufindr][0] != ';') // TODO - find out why empty comment lines get through to here...
                {
		  Serial.print("// Unknown command:");
		  Serial.println(cmdbuffer[bufindr]);
                }
	}

	ClearToSend();

}

void FlushSerialRequestResend()
{
	//char cmdbuffer[bufindr][100]="Resend:";
	Serial.flush();
	Serial.print("rs ");
        ok_sent = true;  // No it's not - rs was sent instead; but this does the right thing...
	Serial.println(gcode_LastN + 1);
	ClearToSend();
}

void ClearToSend()
{
	previous_millis_cmd = millis();
	#ifdef SDSUPPORT
	if(fromsd[bufindr])
		return;
	#endif
        if(!ok_sent)
	  Serial.println("ok");
        ok_sent = false;
}

inline void get_coordinates()
{
	for(int i=0; i < NUM_AXIS; i++) {
		if(code_seen(axis_codes[i])) destination[i] = (float)code_value() + (axis_relative_modes[i] || relative_mode)*current_position[i];
		else destination[i] = current_position[i];                                                       //Are these else lines really needed?
	}
	if(code_seen('F')) {
		next_feedrate = code_value();
		if(next_feedrate > 0.0) destination_feedrate = next_feedrate;
	}
}

void manage_heater()
{
	if((millis() - previous_millis_heater) < HEATER_CHECK_INTERVAL )
		return;
	previous_millis_heater = millis();
#ifdef HEATER_USES_THERMISTOR
	current_raw = analogRead(TEMP_0_PIN); 
  #ifdef DEBUG_HEAT_MGMT
	log_int("_HEAT_MGMT - analogRead(TEMP_0_PIN)", current_raw);
	log_int("_HEAT_MGMT - NUMTEMPS", NUMTEMPS);
  #endif
	// When using thermistor, when the heater is colder than targer temp, we get a higher analog reading than target, 
	// this switches it up so that the reading appears lower than target for the control logic.
	current_raw = 1023 - current_raw;
#elif defined HEATER_USES_AD595
	current_raw = analogRead(TEMP_0_PIN);    
#elif defined HEATER_USES_MAX6675
	current_raw = read_max6675();
#endif
#ifdef SMOOTHING
	if (!nma) nma = SMOOTHFACTOR * current_raw;
	nma = (nma + current_raw) - (nma / SMOOTHFACTOR);
	current_raw = nma / SMOOTHFACTOR;
#endif
#ifdef WATCHPERIOD
	if(watchmillis && millis() - watchmillis > WATCHPERIOD)
        {
		if(watch_raw + 1 >= current_raw)
                {
			target_raw = 0;
			WRITE(HEATER_0_PIN,LOW);
  #if LED_PIN>-1
			WRITE(LED_PIN,LOW);
  #endif
		}else
                {
			watchmillis = 0;
		}
	}
#endif
#ifdef MINTEMP
	if(current_raw <= minttemp)
		target_raw = 0;
#endif
#ifdef MAXTEMP
	if(current_raw >= maxttemp) {
		target_raw = 0;
	}
#endif
#if (TEMP_0_PIN > -1) || defined (HEATER_USES_MAX6675) || defined (HEATER_USES_AD595)
  #ifdef PIDTEMP
	error = target_raw - current_raw;
	pTerm = (PID_PGAIN * error) / 100;
	temp_iState += error;
	temp_iState = constrain(temp_iState, temp_iState_min, temp_iState_max);
	iTerm = (PID_IGAIN * temp_iState) / 100;
	dTerm = (PID_DGAIN * (current_raw - temp_dState)) / 100;
	temp_dState = current_raw;
	analogWrite(HEATER_0_PIN, constrain(pTerm + iTerm - dTerm, 0, PID_MAX));
  #else
		if(current_raw >= target_raw)
		{
			WRITE(HEATER_0_PIN,LOW);
			#if LED_PIN>-1
			WRITE(LED_PIN,LOW);
			#endif
		}
		else 
		{
			WRITE(HEATER_0_PIN,HIGH);
			#if LED_PIN > -1
			WRITE(LED_PIN,HIGH);
			#endif
		}
  #endif
#endif

	if(millis() - previous_millis_bed_heater < BED_CHECK_INTERVAL)
		return;
	previous_millis_bed_heater = millis();
#ifndef TEMP_1_PIN
	return;
#endif
#if TEMP_1_PIN == -1
	return;
#else

  #ifdef BED_USES_THERMISTOR

		current_bed_raw = analogRead(TEMP_1_PIN);   
    #ifdef DEBUG_HEAT_MGMT
	log_int("_HEAT_MGMT - analogRead(TEMP_1_PIN)", current_bed_raw);
	log_int("_HEAT_MGMT - BNUMTEMPS", BNUMTEMPS);
    #endif               

	// If using thermistor, when the heater is colder than targer temp, we get a higher analog reading than target, 
	// this switches it up so that the reading appears lower than target for the control logic.
	current_bed_raw = 1023 - current_bed_raw;
  #elif defined BED_USES_AD595
	current_bed_raw = analogRead(TEMP_1_PIN);                  

  #endif


	if(current_bed_raw >= target_bed_raw)
	{
		WRITE(HEATER_1_PIN,LOW);
	}
	else 
	{
		WRITE(HEATER_1_PIN,HIGH);
	}
#endif
}


int temp2analogu(int celsius, const short table[][2], int numtemps, int source) {
	#if defined (HEATER_USES_THERMISTOR) || defined (BED_USES_THERMISTOR)
	if(source==1){
		int raw = 0;
		byte i;

		for (i=1; i<numtemps; i++)
		{
			if (table[i][1] < celsius)
			{
				raw = table[i-1][0] + 
				(celsius - table[i-1][1]) * 
				(table[i][0] - table[i-1][0]) /
				(table[i][1] - table[i-1][1]);

				break;
			}
		}

		// Overflow: Set to last value in the table
		if (i == numtemps) raw = table[i-1][0];

		return 1023 - raw;
	}
	#elif defined (HEATER_USES_AD595) || defined (BED_USES_AD595)
	if(source==2)
		return celsius * 1024 / (500);
	#elif defined (HEATER_USES_MAX6675) || defined (BED_USES_MAX6675)
	if(source==3)
		return celsius * 4;
	#endif
	return -1;
}

int analog2tempu(int raw,const short table[][2], int numtemps, int source) {
	#if defined (HEATER_USES_THERMISTOR) || defined (BED_USES_THERMISTOR)
	if(source==1){
		int celsius = 0;
		byte i;

		raw = 1023 - raw;

		for (i=1; i<numtemps; i++)
		{
			if (table[i][0] > raw)
			{
				celsius  = table[i-1][1] + 
				(raw - table[i-1][0]) * 
				(table[i][1] - table[i-1][1]) /
				(table[i][0] - table[i-1][0]);

				break;
			}
		}

		// Overflow: Set to last value in the table
		if (i == numtemps) celsius = table[i-1][1];

		return celsius;
	}
	#elif defined (HEATER_USES_AD595) || defined (BED_USES_AD595)
	if(source==2)
		return raw * 500 / 1024;
	#elif defined (HEATER_USES_MAX6675) || defined (BED_USES_MAX6675)
	if(source==3)
		return raw / 4;
	#endif
	return -1;
}


inline void kill()
{
  #if TEMP_0_PIN > -1
	target_raw=0;
	WRITE(HEATER_0_PIN,LOW);
  #endif
  #if TEMP_1_PIN > -1
	target_bed_raw=0;
	if(HEATER_1_PIN > -1) WRITE(HEATER_1_PIN,LOW);
  #endif
  #ifdef ENABLE_PIN // For early Sanguinololus
        WRITE(ENABLE_PIN,!ENABLE_ON);
  #else
	disable_x();
	disable_y();
	disable_z();
	disable_e();
  #endif
	if(PS_ON_PIN > -1) pinMode(PS_ON_PIN,INPUT);
}

inline void manage_inactivity(byte debug) { 
	if( (millis()-previous_millis_cmd) >  max_inactive_time ) if(max_inactive_time) kill(); 
	if( (millis()-previous_millis_cmd) >  stepper_inactive_time ) if(stepper_inactive_time) { disable_x(); disable_y(); disable_z(); disable_e(); }
}


// ************************************************************************************************************************************

// Code for RepRap-style accelerations

#ifdef REPRAP_ACC

// The number of mm below which distances are insignificant (one tenth the
// resolution of the machine is the default value).
#define SMALL_DISTANCE 0.01
// Useful to have its square
#define SMALL_DISTANCE2 (SMALL_DISTANCE*SMALL_DISTANCE)

bool nullmove, real_move;
bool direction_f;
bool x_can_step, y_can_step, z_can_step, e_can_step, f_can_step;
bool direction_x, direction_y, direction_z, direction_e;
long total_steps, t_scale;
long dda_counter_x, dda_counter_y, dda_counter_z, dda_counter_e, dda_counter_f;
long current_steps_x, current_steps_y, current_steps_z, current_steps_e, current_steps_f;
long target_steps_x, target_steps_y, target_steps_z, target_steps_e, target_steps_f;
long delta_steps_x, delta_steps_y, delta_steps_z, delta_steps_e, delta_steps_f;	
float position, target, diff, distance, f_total_steps;
//long integer_distance;
unsigned long start_time, time_increment;


/*

Calculate delay between steps in microseconds.  Here it is in English:

60000000.0*distance/feedrate_now  = move duration in microseconds
move duration/total_steps = time between steps for master axis.

feedrate_now is in mm/minute, 
distance is in mm, 
integer_distance is 3000000.0*distance

To prevent long overflow, we work in increments of 50 microseconds; hence 
the 1,200,000 rather than 60,000,000.
 */

//#define DISTANCE_MULTIPLIER 1200000.0
//#define MICRO_RES 50

//inline long calculate_feedrate_delay(const long& feedrate_now)
//{  
//  return MICRO_RES*(integer_distance/(feedrate_now*total_steps));	
//}

inline unsigned long calculate_feedrate_delay(const float& feedrate_now)
{  

	// Calculate delay between steps in microseconds.  Here it is in English:
	// (feedrate is in mm/minute, distance is in mm)
	// 60000000.0*distance/feedrate  = move duration in microseconds
	// move duration/total_steps = time between steps for master axis.

	return (unsigned long)lround( (distance*60000000.0) / (feedrate_now*f_total_steps) );	
}

inline void do_x_step()
{
	digitalWrite(X_STEP_PIN, HIGH);
	//delayMicroseconds(3);
	digitalWrite(X_STEP_PIN, LOW);
}

inline void do_y_step()
{
	digitalWrite(Y_STEP_PIN, HIGH);
	//delayMicroseconds(3);
	digitalWrite(Y_STEP_PIN, LOW);
}

inline void do_z_step()
{
	digitalWrite(Z_STEP_PIN, HIGH);
	//delayMicroseconds(3);
	digitalWrite(Z_STEP_PIN, LOW);
}

inline void do_e_step()
{
	digitalWrite(E_STEP_PIN, HIGH);
	// delayMicroseconds(3);
	digitalWrite(E_STEP_PIN, LOW);
}

#define ALWAYS_UPDATE 1
#define CONDITIONAL_UPDATE 2
#define NEVER_UPDATE 3

inline void coord_to_steps(const float& current, const float& destination, long& current_steps, const long& steps_per_unit,
		long& target_steps, long& delta_steps, bool& dir, unsigned char dist_check)
{
	position = current;
	current_steps = lround(position*steps_per_unit);
	target = destination;
	target_steps = lround(target*steps_per_unit);
	delta_steps = target_steps - current_steps;
	if(delta_steps >= 0) dir = 1;
	else
	{
		dir = 0;
		delta_steps = -delta_steps;
	}
	switch(dist_check)
	{
	case CONDITIONAL_UPDATE:
		if(distance > SMALL_DISTANCE2)  // Don't update with E if X, Y or Z going somewhere already
			return;
	case ALWAYS_UPDATE:
		diff = target - position;
		distance += diff*diff;
		break;
	case NEVER_UPDATE:
	default:
		break;
	}
}

inline void execute_move()
{

	if(destination_feedrate > max_feedrate[0]) destination_feedrate = max_feedrate[0];
	if(destination_feedrate<10) destination_feedrate=10; 

        if (destination[0] < 0) 
        {
              check_endstops = true;
              if (min_software_endstops) destination[0] = 0.0;
        }
        
        if (destination[1] < 0) 
        {
              check_endstops = true;
              if (min_software_endstops) destination[1] = 0.0;
        }
        
        if (destination[2] < 0) 
        {
              check_endstops = true;
              if (min_software_endstops) destination[2] = 0.0;
        }

	if (max_software_endstops) 
	{
		if (destination[0] > X_MAX_LENGTH) destination[0] = X_MAX_LENGTH;
		if (destination[1] > Y_MAX_LENGTH) destination[1] = Y_MAX_LENGTH;
		if (destination[2] > Z_MAX_LENGTH) destination[2] = Z_MAX_LENGTH;
	}

	nullmove = false;

	distance = 0.0;

	coord_to_steps(current_position[0], destination[0], current_steps_x, axis_steps_per_unit[0],
			target_steps_x, delta_steps_x, direction_x, ALWAYS_UPDATE);
	coord_to_steps(current_position[1], destination[1], current_steps_y, axis_steps_per_unit[1],
			target_steps_y, delta_steps_y, direction_y, ALWAYS_UPDATE);
	coord_to_steps(current_position[2], destination[2], current_steps_z, axis_steps_per_unit[2],
			target_steps_z, delta_steps_z, direction_z, ALWAYS_UPDATE);
	coord_to_steps(current_position[3], destination[3], current_steps_e, axis_steps_per_unit[3],
			target_steps_e, delta_steps_e, direction_e, CONDITIONAL_UPDATE);              

	if(distance < SMALL_DISTANCE2) // If only F changes, do it in one shot
	{
		nullmove = true;
		current_feedrate = destination_feedrate;
		return; 
	}    

	coord_to_steps(current_feedrate, destination_feedrate, current_steps_f, 1,
			target_steps_f, delta_steps_f, direction_f, NEVER_UPDATE);  

	distance = sqrt(distance); 
	//integer_distance = lround(distance*DISTANCE_MULTIPLIER);  

	total_steps = max(delta_steps_x, delta_steps_y);
	total_steps = max(total_steps, delta_steps_z);
	total_steps = max(total_steps, delta_steps_e);

	// If we're not going anywhere, flag the fact (defensive programming)

	if(total_steps <= 0)
	{
		f_total_steps = 0.0;
		nullmove = true;
		current_feedrate = destination_feedrate;
		return;
	}    

	// Rescale the feedrate so it doesn't take lots of steps to do

	t_scale = 1;
	if(delta_steps_f > total_steps)
	{
		t_scale = delta_steps_f/total_steps;
		if(t_scale >= 3)
		{
			target_steps_f = target_steps_f/t_scale;
			current_steps_f = current_steps_f/t_scale;
			delta_steps_f = abs(target_steps_f - current_steps_f);
			if(delta_steps_f > total_steps)
				total_steps =  delta_steps_f;
		} else
		{
			t_scale = 1;
			total_steps =  delta_steps_f;
		}
	}  

	f_total_steps = (float)total_steps;
	dda_counter_x = -total_steps/2;
	dda_counter_y = dda_counter_x;
	dda_counter_z = dda_counter_x;
	dda_counter_e = dda_counter_x;
	dda_counter_f = dda_counter_x;

	time_increment = calculate_feedrate_delay((float)(t_scale*current_steps_f));

	if(delta_steps_x) enable_x();
	if(delta_steps_y) enable_y();
	if(delta_steps_z) enable_z();
	if(delta_steps_e) enable_e();

	if (direction_x) digitalWrite(X_DIR_PIN,!INVERT_X_DIR);
	else digitalWrite(X_DIR_PIN,INVERT_X_DIR);
	if (direction_y) digitalWrite(Y_DIR_PIN,!INVERT_Y_DIR);
	else digitalWrite(Y_DIR_PIN,INVERT_Y_DIR);
	if (direction_z) digitalWrite(Z_DIR_PIN,!INVERT_Z_DIR);
	else digitalWrite(Z_DIR_PIN,INVERT_Z_DIR);
	if (direction_e) digitalWrite(E_DIR_PIN,!INVERT_E_DIR);
	else digitalWrite(E_DIR_PIN,INVERT_E_DIR);

	linear_move(); 
        check_endstops = false;
}

inline bool can_step_switch(const long& here, const long& there, bool direction, int minstop, int maxstop)
{
	if(here == there)
		return false;

	if(check_endstops)
	{
		if(direction)
		{
			if(maxstop >= 0)
				return digitalRead(maxstop) == ENDSTOPS_INVERTING;
		} else
		{
			if(minstop >= 0)
				return digitalRead(minstop) == ENDSTOPS_INVERTING;
		}
	}
	return true;
}

inline bool can_step(const long& here, const long& there)
{
	return here != there;
}

void linear_move() // make linear move with preset speeds and destinations, see G0 and G1
{
	if(nullmove)
	{
		nullmove = false;
		return;
	}



	do
	{     
		start_time = micros();

		x_can_step = can_step_switch(current_steps_x, target_steps_x, direction_x, X_MIN_PIN, X_MAX_PIN);
		y_can_step = can_step_switch(current_steps_y, target_steps_y, direction_y, Y_MIN_PIN, Y_MAX_PIN);
		z_can_step = can_step_switch(current_steps_z, target_steps_z, direction_z, Z_MIN_PIN, Z_MAX_PIN);
		e_can_step = can_step(current_steps_e, target_steps_e);
		f_can_step = can_step(current_steps_f, target_steps_f);

		real_move = false;

		if (x_can_step)
		{
			dda_counter_x += delta_steps_x;

			if (dda_counter_x > 0)
			{
				do_x_step();
				real_move = true;
				dda_counter_x -= total_steps;

				if (direction_x)
					current_steps_x++;
				else
					current_steps_x--;
			}
		}

		if (y_can_step)
		{
			dda_counter_y += delta_steps_y;

			if (dda_counter_y > 0)
			{
				do_y_step();
				real_move = true;
				dda_counter_y -= total_steps;

				if (direction_y)
					current_steps_y++;
				else
					current_steps_y--;
			}
		}

		if (z_can_step)
		{
			dda_counter_z += delta_steps_z;

			if (dda_counter_z > 0)
			{
				do_z_step();
				real_move = true;
				dda_counter_z -= total_steps;

				if (direction_z)
					current_steps_z++;
				else
					current_steps_z--;
			}
		}

		if (e_can_step)
		{
			dda_counter_e += delta_steps_e;

			if (dda_counter_e > 0)
			{

				do_e_step();
				real_move = true;
				dda_counter_e -= total_steps;

				if (direction_e)
					current_steps_e++;
				else
					current_steps_e--;
			}
		}

		if (f_can_step)
		{
			dda_counter_f += delta_steps_f;

			if (dda_counter_f > 0)
			{
				dda_counter_f -= total_steps;
				if (direction_f)
					current_steps_f++;
				else
					current_steps_f--;
				time_increment = calculate_feedrate_delay((float)(t_scale*current_steps_f));
			} 
		}

		//if(real_move) // If only F has changed, no point in delaying 
		//step_time += time_increment; 

		while(micros() - start_time < time_increment) // This should work even when micros() overflows.  See http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1292358124
		{
			if((millis() - previous_millis_heater) >= 500)
			{
				manage_heater();
				previous_millis_heater = millis();
				manage_inactivity(2);
			}
		}            
	} while (x_can_step || y_can_step || z_can_step  || e_can_step || f_can_step);


	if(DISABLE_X) disable_x();
	if(DISABLE_Y) disable_y();
	if(DISABLE_Z) disable_z();
	if(DISABLE_E) disable_e();

	if(check_endstops && (digitalRead(X_MIN_PIN) != ENDSTOPS_INVERTING))
		current_position[0] = 0.0;
	else
		current_position[0] = destination[0];

	if(check_endstops && (digitalRead(Y_MIN_PIN) != ENDSTOPS_INVERTING))
		current_position[1] = 0.0;
	else
		current_position[1] = destination[1];

	if(check_endstops && (digitalRead(Z_MIN_PIN) != ENDSTOPS_INVERTING))
		current_position[2] = 0.0;
	else
		current_position[2] = destination[2];    

	current_position[3] = destination[3];
	current_feedrate = destination_feedrate;

}

#else

	//******************************************************************************************************************

	// Code for ordinary G-Code F behaviour

	void execute_move()
{
	//Find direction
	for(int i=0; i < NUM_AXIS; i++) {
		if(destination[i] >= current_position[i]) move_direction[i] = 1;
		else move_direction[i] = 0;
	}


	if (min_software_endstops) {
		if (destination[0] < 0) destination[0] = 0.0;
		if (destination[1] < 0) destination[1] = 0.0;
		if (destination[2] < 0) destination[2] = 0.0;
	}

	if (max_software_endstops) {
		if (destination[0] > X_MAX_LENGTH) destination[0] = X_MAX_LENGTH;
		if (destination[1] > Y_MAX_LENGTH) destination[1] = Y_MAX_LENGTH;
		if (destination[2] > Z_MAX_LENGTH) destination[2] = Z_MAX_LENGTH;
	}

	for(int i=0; i < NUM_AXIS; i++) {
		axis_diff[i] = destination[i] - current_position[i];
		move_steps_to_take[i] = abs(axis_diff[i]) * axis_steps_per_unit[i];
	}
	if(destination_feedrate < 10)
		destination_feedrate = 10;

	//Feedrate calc based on XYZ travel distance
	float xy_d;
	//Check for cases where only one axis is moving - handle those without float sqrt
	if(abs(axis_diff[0]) > 0 && abs(axis_diff[1]) == 0 && abs(axis_diff[2])==0)
		d=abs(axis_diff[0]);
	else if(abs(axis_diff[0]) == 0 && abs(axis_diff[1]) > 0 && abs(axis_diff[2])==0)
		d=abs(axis_diff[1]);
	else if(abs(axis_diff[0]) == 0 && abs(axis_diff[1]) == 0 && abs(axis_diff[2])>0)
		d=abs(axis_diff[2]);
	//two or three XYZ axes moving
	else if(abs(axis_diff[0]) > 0 || abs(axis_diff[1]) > 0) { //X or Y or both
		xy_d = sqrt(axis_diff[0] * axis_diff[0] + axis_diff[1] * axis_diff[1]);
		//check if Z involved - if so interpolate that too
		d = (abs(axis_diff[2]>0))?sqrt(xy_d * xy_d + axis_diff[2] * axis_diff[2]):xy_d;
	}
	else if(abs(axis_diff[3]) > 0)
		d = abs(axis_diff[3]);
	else{ //zero length move
		#ifdef DEBUG_PREPARE_MOVE

		log_message("_PREPARE_MOVE - No steps to take!");

		#endif
		return;
	}
	time_for_move = (d / (destination_feedrate / 60000000.0) );
	//Check max feedrate for each axis is not violated, update time_for_move if necessary
	for(int i = 0; i < NUM_AXIS; i++) {
		if(move_steps_to_take[i] && abs(axis_diff[i]) / (time_for_move / 60000000.0) > max_feedrate[i]) {
			time_for_move = time_for_move / max_feedrate[i] * (abs(axis_diff[i]) / (time_for_move / 60000000.0));
		}
	}
	//Calculate the full speed stepper interval for each axis
	for(int i=0; i < NUM_AXIS; i++) {
		if(move_steps_to_take[i]) axis_interval[i] = time_for_move / move_steps_to_take[i] * 100;
	}

	#ifdef DEBUG_PREPARE_MOVE
	log_float("_PREPARE_MOVE - Move distance on the XY plane", xy_d);
	log_float("_PREPARE_MOVE - Move distance on the XYZ space", d);
	log_int("_PREPARE_MOVE - Commanded feedrate", destination_feedrate);
	log_float("_PREPARE_MOVE - Constant full speed move time", time_for_move);
	log_float_array("_PREPARE_MOVE - Destination", destination, NUM_AXIS);
	log_float_array("_PREPARE_MOVE - Current position", current_position, NUM_AXIS);
	log_ulong_array("_PREPARE_MOVE - Steps to take", move_steps_to_take, NUM_AXIS);
	log_long_array("_PREPARE_MOVE - Axes full speed intervals", axis_interval, NUM_AXIS);
	#endif

	unsigned long move_steps[NUM_AXIS];
	for(int i=0; i < NUM_AXIS; i++)
		move_steps[i] = move_steps_to_take[i];
	linear_move(move_steps); // make the move
}


inline void linear_move(unsigned long axis_steps_remaining[]) // make linear move with preset speeds and destinations, see G0 and G1
{
	//Determine direction of movement
	if (destination[0] > current_position[0]) WRITE(X_DIR_PIN,!INVERT_X_DIR);
	else WRITE(X_DIR_PIN,INVERT_X_DIR);
	if (destination[1] > current_position[1]) WRITE(Y_DIR_PIN,!INVERT_Y_DIR);
	else WRITE(Y_DIR_PIN,INVERT_Y_DIR);
	if (destination[2] > current_position[2]) WRITE(Z_DIR_PIN,!INVERT_Z_DIR);
	else WRITE(Z_DIR_PIN,INVERT_Z_DIR);
	if (destination[3] > current_position[3]) WRITE(E_DIR_PIN,!INVERT_E_DIR);
	else WRITE(E_DIR_PIN,INVERT_E_DIR);
	movereset:
		#if (X_MIN_PIN > -1) 
			if(!move_direction[0]) if(READ(X_MIN_PIN) != ENDSTOPS_INVERTING) axis_steps_remaining[0]=0;
	#endif
	#if (Y_MIN_PIN > -1) 
		if(!move_direction[1]) if(READ(Y_MIN_PIN) != ENDSTOPS_INVERTING) axis_steps_remaining[1]=0;
	#endif
	#if (Z_MIN_PIN > -1) 
		if(!move_direction[2]) if(READ(Z_MIN_PIN) != ENDSTOPS_INVERTING) axis_steps_remaining[2]=0;
	#endif
	#if (X_MAX_PIN > -1) 
		if(move_direction[0]) if(READ(X_MAX_PIN) != ENDSTOPS_INVERTING) axis_steps_remaining[0]=0;
	#endif
	#if (Y_MAX_PIN > -1) 
		if(move_direction[1]) if(READ(Y_MAX_PIN) != ENDSTOPS_INVERTING) axis_steps_remaining[1]=0;
	#endif
	# if(Z_MAX_PIN > -1) 
		if(move_direction[2]) if(READ(Z_MAX_PIN) != ENDSTOPS_INVERTING) axis_steps_remaining[2]=0;
	#endif


	//Only enable axis that are moving. If the axis doesn't need to move then it can stay disabled depending on configuration.
	// TODO: maybe it's better to refactor into a generic enable(int axis) function, that will probably take more ram,
	// but will reduce code size
	if(axis_steps_remaining[0]) enable_x();
	if(axis_steps_remaining[1]) enable_y();
	if(axis_steps_remaining[2]) enable_z();
	if(axis_steps_remaining[3]) enable_e();

	//Define variables that are needed for the Bresenham algorithm. Please note that  Z is not currently included in the Bresenham algorithm.
	unsigned long delta[] = {axis_steps_remaining[0], axis_steps_remaining[1], axis_steps_remaining[2], axis_steps_remaining[3]}; //TODO: implement a "for" to support N axes
	long axis_error[NUM_AXIS];
	int primary_axis;
	if(delta[1] > delta[0] && delta[1] > delta[2] && delta[1] > delta[3]) primary_axis = 1;
	else if (delta[0] >= delta[1] && delta[0] > delta[2] && delta[0] > delta[3]) primary_axis = 0;
	else if (delta[2] >= delta[0] && delta[2] >= delta[1] && delta[2] > delta[3]) primary_axis = 2;
	else primary_axis = 3;
	unsigned long steps_remaining = delta[primary_axis];
	unsigned long steps_to_take = steps_remaining;
	for(int i=0; i < NUM_AXIS; i++){
		if(i != primary_axis) axis_error[i] = delta[primary_axis] / 2;
		steps_taken[i]=0;
	}
	interval = axis_interval[primary_axis];
	bool is_print_move = delta[3] > 0;
	#ifdef DEBUG_BRESENHAM
	log_int("_BRESENHAM - Primary axis", primary_axis);
	log_int("_BRESENHAM - Primary axis full speed interval", interval);
	log_ulong_array("_BRESENHAM - Deltas", delta, NUM_AXIS);
	log_long_array("_BRESENHAM - Errors", axis_error, NUM_AXIS);
	#endif

	//If acceleration is enabled, do some Bresenham calculations depending on which axis will lead it.
	#ifdef RAMP_ACCELERATION
	long max_speed_steps_per_second;
	long min_speed_steps_per_second;
	max_interval = axis_max_interval[primary_axis];
	#ifdef DEBUG_RAMP_ACCELERATION
	log_ulong_array("_RAMP_ACCELERATION - Teoric step intervals at move start", axis_max_interval, NUM_AXIS);
	#endif
	unsigned long new_axis_max_intervals[NUM_AXIS];
	max_speed_steps_per_second = 100000000 / interval;
	min_speed_steps_per_second = 100000000 / max_interval; //TODO: can this be deleted?
	//Calculate start speeds based on moving axes max start speed constraints.
	int slowest_start_axis = primary_axis;
	unsigned long slowest_start_axis_max_interval = max_interval;
	for(int i = 0; i < NUM_AXIS; i++)
		if (axis_steps_remaining[i] >0 && 
				i != primary_axis && 
				axis_max_interval[i] * axis_steps_remaining[i]/ axis_steps_remaining[slowest_start_axis] > slowest_start_axis_max_interval) {
			slowest_start_axis = i;
			slowest_start_axis_max_interval = axis_max_interval[i];
		}
	for(int i = 0; i < NUM_AXIS; i++)
		if(axis_steps_remaining[i] >0) {
			// multiplying slowest_start_axis_max_interval by axis_steps_remaining[slowest_start_axis]
			// could lead to overflows when we have long distance moves (say, 390625*390625 > sizeof(unsigned long))
			float steps_remaining_ratio = (float) axis_steps_remaining[slowest_start_axis] / axis_steps_remaining[i];
			new_axis_max_intervals[i] = slowest_start_axis_max_interval * steps_remaining_ratio;

			if(i == primary_axis) {
				max_interval = new_axis_max_intervals[i];
				min_speed_steps_per_second = 100000000 / max_interval;
			}
		}
	//Calculate slowest axis plateau time
	float slowest_axis_plateau_time = 0;
	for(int i=0; i < NUM_AXIS ; i++) {
		if(axis_steps_remaining[i] > 0) {
			if(is_print_move && axis_steps_remaining[i] > 0) slowest_axis_plateau_time = max(slowest_axis_plateau_time,
					(100000000.0 / axis_interval[i] - 100000000.0 / new_axis_max_intervals[i]) / (float) axis_steps_per_sqr_second[i]);
			else if(axis_steps_remaining[i] > 0) slowest_axis_plateau_time = max(slowest_axis_plateau_time,
					(100000000.0 / axis_interval[i] - 100000000.0 / new_axis_max_intervals[i]) / (float) axis_travel_steps_per_sqr_second[i]);
		}
	}
	//Now we can calculate the new primary axis acceleration, so that the slowest axis max acceleration is not violated
	steps_per_sqr_second = (100000000.0 / axis_interval[primary_axis] - 100000000.0 / new_axis_max_intervals[primary_axis]) / slowest_axis_plateau_time;
	plateau_steps = (long) ((steps_per_sqr_second / 2.0 * slowest_axis_plateau_time + min_speed_steps_per_second) * slowest_axis_plateau_time);
	#ifdef DEBUG_RAMP_ACCELERATION
	log_int("_RAMP_ACCELERATION - Start speed limiting axis", slowest_start_axis);
	log_ulong("_RAMP_ACCELERATION - Limiting axis start interval", slowest_start_axis_max_interval);
	log_ulong_array("_RAMP_ACCELERATION - Actual step intervals at move start", new_axis_max_intervals, NUM_AXIS);
	#endif
	#endif

	unsigned long steps_done = 0;
	#ifdef RAMP_ACCELERATION
	plateau_steps *= 1.01; // This is to compensate we use discrete intervals
	acceleration_enabled = true;
	unsigned long full_interval = interval;
	if(interval > max_interval) acceleration_enabled = false;
	boolean decelerating = false;
	#endif

	unsigned long start_move_micros = micros();
	for(int i = 0; i < NUM_AXIS; i++) {
		axis_previous_micros[i] = start_move_micros * 100;
	}

	#ifdef DISABLE_CHECK_DURING_TRAVEL
	//If the move time is more than allowed in DISABLE_CHECK_DURING_TRAVEL, let's
	// consider this a print move and perform heat management during it
	if(time_for_move / 1000 > DISABLE_CHECK_DURING_TRAVEL) is_print_move = true;
	//else, if the move is a retract, consider it as a travel move for the sake of this feature
	else if(delta[3]>0 && delta[0] + delta[1] + delta[2] == 0) is_print_move = false;
	#ifdef DEBUG_DISABLE_CHECK_DURING_TRAVEL
	log_bool("_DISABLE_CHECK_DURING_TRAVEL - is_print_move", is_print_move);
	#endif
	#endif

	#ifdef DEBUG_MOVE_TIME
	unsigned long startmove = micros();
	#endif

	//move until no more steps remain 
	while(axis_steps_remaining[0] + axis_steps_remaining[1] + axis_steps_remaining[2] + axis_steps_remaining[3] > 0) {
		#if defined RAMP_ACCELERATION && defined DISABLE_CHECK_DURING_ACC
		if(!accelerating && !decelerating) {
			//If more that HEATER_CHECK_INTERVAL ms have passed since previous heating check, adjust temp
			#ifdef DISABLE_CHECK_DURING_TRAVEL
			if(is_print_move)
				#endif
				manage_heater();
		}
		#else
			#ifdef DISABLE_CHECK_DURING_MOVE
			{} //Do nothing
		#else
			//If more that HEATER_CHECK_INTERVAL ms have passed since previous heating check, adjust temp
			#ifdef DISABLE_CHECK_DURING_TRAVEL
			if(is_print_move)
				#endif
				manage_heater();
		#endif
		#endif
		#ifdef RAMP_ACCELERATION
		//If acceleration is enabled on this move and we are in the acceleration segment, calculate the current interval
		if (acceleration_enabled && steps_done == 0) {
			interval = max_interval;
		} else if (acceleration_enabled && steps_done <= plateau_steps) {
			long current_speed = (long) ((((long) steps_per_sqr_second) / 100)
					* ((micros() - start_move_micros)  / 100)/100 + (long) min_speed_steps_per_second);
			interval = 100000000 / current_speed;
			if (interval < full_interval) {
				accelerating = false;
				interval = full_interval;
			}
			if (steps_done >= steps_to_take / 2) {
				plateau_steps = steps_done;
				max_speed_steps_per_second = 100000000 / interval;
				accelerating = false;
			}
		} else if (acceleration_enabled && steps_remaining <= plateau_steps) { //(interval > minInterval * 100) {
			if (!accelerating) {
				start_move_micros = micros();
				accelerating = true;
				decelerating = true;
			}				
			long current_speed = (long) ((long) max_speed_steps_per_second - ((((long) steps_per_sqr_second) / 100)
					* ((micros() - start_move_micros) / 100)/100));
			interval = 100000000 / current_speed;
			if (interval > max_interval)
				interval = max_interval;
		} else {
			//Else, we are just use the full speed interval as current interval
			interval = full_interval;
			accelerating = false;
		}
		#endif

		//If there are x or y steps remaining, perform Bresenham algorithm
		if(axis_steps_remaining[primary_axis]) {
			#if (X_MIN_PIN > -1) 
				if(!move_direction[0]) if(READ(X_MIN_PIN) != ENDSTOPS_INVERTING) if(primary_axis==0) break; else if(axis_steps_remaining[0]) axis_steps_remaining[0]=0;
			#endif
			#if (Y_MIN_PIN > -1) 
				if(!move_direction[1]) if(READ(Y_MIN_PIN) != ENDSTOPS_INVERTING) if(primary_axis==1) break; else if(axis_steps_remaining[1]) axis_steps_remaining[1]=0;
			#endif
			#if (X_MAX_PIN > -1) 
				if(move_direction[0]) if(READ(X_MAX_PIN) != ENDSTOPS_INVERTING) if(primary_axis==0) break; else if(axis_steps_remaining[0]) axis_steps_remaining[0]=0;
			#endif
			#if (Y_MAX_PIN > -1) 
				if(move_direction[1]) if(READ(Y_MAX_PIN) != ENDSTOPS_INVERTING) if(primary_axis==1) break; else if(axis_steps_remaining[1]) axis_steps_remaining[1]=0;
			#endif
			#if (Z_MIN_PIN > -1) 
				if(!move_direction[2]) if(READ(Z_MIN_PIN) != ENDSTOPS_INVERTING) if(primary_axis==2) break; else if(axis_steps_remaining[2]) axis_steps_remaining[2]=0;
			#endif
			#if (Z_MAX_PIN > -1) 
				if(move_direction[2]) if(READ(Z_MAX_PIN) != ENDSTOPS_INVERTING) if(primary_axis==2) break; else if(axis_steps_remaining[2]) axis_steps_remaining[2]=0;
			#endif
			timediff = micros() * 100 - axis_previous_micros[primary_axis];
			if(timediff<0){//check for overflow
				axis_previous_micros[primary_axis]=micros()*100;
				timediff=interval/2; //approximation
			}
			while(((unsigned long)timediff) >= interval && axis_steps_remaining[primary_axis] > 0) {
				steps_done++;
				steps_remaining--;
				axis_steps_remaining[primary_axis]--; timediff -= interval;
				do_step(primary_axis);
				axis_previous_micros[primary_axis] += interval;
				for(int i=0; i < NUM_AXIS; i++) if(i != primary_axis && axis_steps_remaining[i] > 0) {
					axis_error[i] = axis_error[i] - delta[i];
					if(axis_error[i] < 0) {
						do_step(i); axis_steps_remaining[i]--;
						axis_error[i] = axis_error[i] + delta[primary_axis];
					}
				}
				#ifdef STEP_DELAY_RATIO
				if(timediff >= interval) delayMicroseconds(long_step_delay_ratio * interval / 10000);
				#endif
				#ifdef STEP_DELAY_MICROS
				if(timediff >= interval) delayMicroseconds(STEP_DELAY_MICROS);
				#endif
			}
		}
	}
	#ifdef DEBUG_MOVE_TIME
	log_ulong("_MOVE_TIME - This move took", micros()-startmove);
	#endif

	if(DISABLE_X) disable_x();
	if(DISABLE_Y) disable_y();
	if(DISABLE_Z) disable_z();
	if(DISABLE_E) disable_e();

	// Update current position partly based on direction, we probably can combine this with the direction code above...
	for(int i=0; i < NUM_AXIS; i++) {
		if (destination[i] > current_position[i]) current_position[i] = current_position[i] + steps_taken[i] /  axis_steps_per_unit[i];
		else current_position[i] = current_position[i] - steps_taken[i] / axis_steps_per_unit[i];
	}
}

void do_step(int axis) {
	switch(axis){
	case 0:
		WRITE(X_STEP_PIN, HIGH);
		break;
	case 1:
		WRITE(Y_STEP_PIN, HIGH);
		break;
	case 2:
		WRITE(Z_STEP_PIN, HIGH);
		break;
	case 3:
		WRITE(E_STEP_PIN, HIGH);
		break;
	}
	steps_taken[axis]+=1;
	WRITE(X_STEP_PIN, LOW);
	WRITE(Y_STEP_PIN, LOW);
	WRITE(Z_STEP_PIN, LOW);
	WRITE(E_STEP_PIN, LOW);
}
#endif

#define HEAT_INTERVAL 250
#ifdef HEATER_USES_MAX6675
unsigned long max6675_previous_millis = 0;
int max6675_temp = 2000;

int read_max6675()
{
	if (millis() - max6675_previous_millis < HEAT_INTERVAL) 
		return max6675_temp;

	max6675_previous_millis = millis();

	max6675_temp = 0;

	#ifdef	PRR
	PRR &= ~(1<<PRSPI);
	#elif defined PRR0
	PRR0 &= ~(1<<PRSPI);
	#endif

	SPCR = (1<<MSTR) | (1<<SPE) | (1<<SPR0);

	// enable TT_MAX6675
	WRITE(MAX6675_SS, 0);

	// ensure 100ns delay - a bit extra is fine
	delay(1);

	// read MSB
	SPDR = 0;
	for (;(SPSR & (1<<SPIF)) == 0;);
	max6675_temp = SPDR;
	max6675_temp <<= 8;

	// read LSB
	SPDR = 0;
	for (;(SPSR & (1<<SPIF)) == 0;);
	max6675_temp |= SPDR;

	// disable TT_MAX6675
	WRITE(MAX6675_SS, 1);

	if (max6675_temp & 4) 
	{
		// thermocouple open
		max6675_temp = 2000;
	}
	else 
	{
		max6675_temp = max6675_temp >> 3;
	}

	return max6675_temp;
}
#endif



#ifdef DEBUG
void log_message(char*   message) {
	Serial.print("// DEBUG"); Serial.println(message);
}

void log_bool(char* message, bool value) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": "); Serial.println(value);
}

void log_int(char* message, int value) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": "); Serial.println(value);
}

void log_long(char* message, long value) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": "); Serial.println(value);
}

void log_float(char* message, float value) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": "); Serial.println(value);
}

void log_uint(char* message, unsigned int value) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": "); Serial.println(value);
}

void log_ulong(char* message, unsigned long value) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": "); Serial.println(value);
}

void log_int_array(char* message, int value[], int array_lenght) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": {");
	for(int i=0; i < array_lenght; i++){
		Serial.print(value[i]);
		if(i != array_lenght-1) Serial.print(", ");
	}
	Serial.println("}");
}

void log_long_array(char* message, long value[], int array_lenght) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": {");
	for(int i=0; i < array_lenght; i++){
		Serial.print(value[i]);
		if(i != array_lenght-1) Serial.print(", ");
	}
	Serial.println("}");
}

void log_float_array(char* message, float value[], int array_lenght) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": {");
	for(int i=0; i < array_lenght; i++){
		Serial.print(value[i]);
		if(i != array_lenght-1) Serial.print(", ");
	}
	Serial.println("}");
}

void log_uint_array(char* message, unsigned int value[], int array_lenght) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": {");
	for(int i=0; i < array_lenght; i++){
		Serial.print(value[i]);
		if(i != array_lenght-1) Serial.print(", ");
	}
	Serial.println("}");
}

void log_ulong_array(char* message, unsigned long value[], int array_lenght) {
	Serial.print("// DEBUG"); Serial.print(message); Serial.print(": {");
	for(int i=0; i < array_lenght; i++){
		Serial.print(value[i]);
		if(i != array_lenght-1) Serial.print(", ");
	}
	Serial.println("}");
}
#endif

