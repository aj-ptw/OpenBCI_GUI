///////////////////////////////////////////////////////////////////////////////
//
// This class configures and manages the connection to the OpenBCI shield for
// the Arduino.  The connection is implemented via a Serial connection.
// The OpenBCI is configured using single letter text commands sent from the
// PC to the Arduino.  The EEG data streams back from the Arduino to the PC
// continuously (once started).  This class defaults to using binary transfer
// for normal operation.
//
// Created: AJ Keller, Feb 2018
//
// Note: this class now expects the data format produced by OpenBCI V3.
//
/////////////////////////////////////////////////////////////////////////////

import java.io.OutputStream; //for logging raw bytes to an output file

//------------------------------------------------------------------------
//                       Classes
//------------------------------------------------------------------------

class Nexus {

  private int nEEGValuesPerPacket = 8; //defined by the data format sent by cyton boards
  private int nAuxValuesPerPacket = 3; //defined by the data format sent by cyton boards
  private DataPacket_ADS1299 rawReceivedDataPacket;
  private DataPacket_ADS1299 missedDataPacket;
  private DataPacket_ADS1299 dataPacket;
  // public int [] validAuxValues = {0, 0, 0};
  // public boolean[] freshAuxValuesAvailable = {false, false, false};
  // public boolean freshAuxValues = false;
  //DataPacket_ADS1299 prevDataPacket;

  private int nAuxValues;
  private boolean isNewDataPacketAvailable = false;
  private OutputStream output; //for debugging  WEA 2014-01-26
  private int prevSampleIndex = 0;
  private int serialErrorCounter = 0;

  private final int fsHzWifi = 250;  //sample rate used by OpenBCI board...set by its Arduino code
  private final int NfftWifi = 256;
  private final float ADS1299_Vref = 4.5f;  //reference voltage for ADC in ADS1299.  set by its hardware
  private float ADS1299_gain = 24.0;  //assumed gain setting for ADS1299.  set by its Arduino code
  private float openBCI_series_resistor_ohms = 2200; // Ohms. There is a series resistor on the 32 bit board.
  private float scale_fac_uVolts_per_count = ADS1299_Vref / ((float)(pow(2, 23)-1)) / ADS1299_gain  * 1000000.f; //ADS1299 datasheet Table 7, confirmed through experiment
  //float LIS3DH_full_scale_G = 4;  // +/- 4G, assumed full scale setting for the accelerometer
  private final float scale_fac_accel_G_per_count = 0.002 / ((float)pow(2, 4));  //assume set to +/4G, so 2 mG per digit (datasheet). Account for 4 bits unused
  //private final float scale_fac_accel_G_per_count = 1.0;  //to test stimulations  //final float scale_fac_accel_G_per_count = 1.0;
  private final float leadOffDrive_amps = 6.0e-9;  //6 nA, set by its Arduino code

  boolean isBiasAuto = true; //not being used?

  private int curBoardMode = BOARD_MODE_DEFAULT;

  //data related to Conor's setup for V3 boards
  final char[] EOT = {'$', '$', '$'};
  char[] prev3chars = {'#', '#', '#'};
  public String potentialFailureMessage = "";
  public String defaultChannelSettings = "";
  public String daisyOrNot = "";
  public int hardwareSyncStep = 0; //start this at 0...
  private long timeOfLastCommand = 0; //used when sync'ing to hardware

  private int curInterface = INTERFACE_HUB_WIFI;
  private int sampleRate = fsHzWifi;
  PApplet mainApplet;

  //some get methods
  public float getSampleRate() {
    return fsHzWifi;
  }

  // TODO: ADJUST getNfft for new sample variable sample rates
  public int getNfft() {
    return NfftWifi;
  }
  public int getBoardMode() {
    return curBoardMode;
  }
  public int getInterface() {
    return curInterface;
  }
  public float get_Vref() {
    return ADS1299_Vref;
  }
  public void set_ADS1299_gain(float _gain) {
    ADS1299_gain = _gain;
    scale_fac_uVolts_per_count = ADS1299_Vref / ((float)(pow(2, 23)-1)) / ADS1299_gain  * 1000000.0; //ADS1299 datasheet Table 7, confirmed through experiment
  }
  public float get_ADS1299_gain() {
    return ADS1299_gain;
  }
  public float get_series_resistor() {
    return openBCI_series_resistor_ohms;
  }
  public float get_scale_fac_uVolts_per_count() {
    return scale_fac_uVolts_per_count;
  }
  public float get_scale_fac_accel_G_per_count() {
    return scale_fac_accel_G_per_count;
  }
  public float get_leadOffDrive_amps() {
    return leadOffDrive_amps;
  }
  public String get_defaultChannelSettings() {
    return defaultChannelSettings;
  }



  public boolean setInterface(int _interface) {
    curInterface = _interface;
    // println("current interface: " + curInterface);
    println("setInterface: curInterface: " + getInterface());
    hub.setProtocol(PROTOCOL_WIFI);
    return true;
  }

  //constructors
  Nexus() {
  };  //only use this if you simply want access to some of the constants
  Nexus(PApplet applet) {
    curInterface = INTERFACE_HUB_WIFI;

    initDataPackets(nEEGValuesPerPacket, nAuxValuesPerPacket);
  }

  public void initDataPackets(int _nEEGValuesPerPacket, int _nAuxValuesPerPacket) {
    nEEGValuesPerPacket = _nEEGValuesPerPacket;
    nAuxValuesPerPacket = _nAuxValuesPerPacket;
    //allocate space for data packet
    rawReceivedDataPacket = new DataPacket_ADS1299(nEEGValuesPerPacket, nAuxValuesPerPacket);  //this should always be 8 channels
    missedDataPacket = new DataPacket_ADS1299(nEEGValuesPerPacket, nAuxValuesPerPacket);  //this should always be 8 channels
    dataPacket = new DataPacket_ADS1299(nEEGValuesPerPacket, nAuxValuesPerPacket);            //this could be 8 or 16 channels
    //set all values to 0 so not null

    for (int i = 0; i < nEEGValuesPerPacket; i++) {
      rawReceivedDataPacket.values[i] = 0;
      //prevDataPacket.values[i] = 0;
    }

    for (int i=0; i < nEEGValuesPerPacket; i++) {
      dataPacket.values[i] = 0;
      missedDataPacket.values[i] = 0;
    }
    for (int i = 0; i < nAuxValuesPerPacket; i++) {
      rawReceivedDataPacket.auxValues[i] = 0;
      dataPacket.auxValues[i] = 0;
      missedDataPacket.auxValues[i] = 0;
      //prevDataPacket.auxValues[i] = 0;
    }
  }

  public int closePort() {
    return hub.disconnectWifi();
  }

  public void writeCommand(String val) {
    if (hub.isHubRunning()) {
      hub.write(String.valueOf(val));
    }
  }

  public boolean write(char val) {
    if (hub.isHubRunning()) {
      hub.sendCommand(val);
      return true;
    }
    return false;
  }

  public boolean write(char val, boolean _readyToSend) {
    // if (isSerial()) {
    //   iSerial.setReadyToSend(_readyToSend);
    // }
    return write(val);
  }

  public boolean write(String out, boolean _readyToSend) {
    // if (isSerial()) {
    //   iSerial.setReadyToSend(_readyToSend);
    // }
    return write(out);
  }

  public boolean write(String out) {
    if (hub.isHubRunning()) {
      hub.write(out);
      return true;
    }
    return false;
  }

  private boolean isSerial () {
    // println("My interface is " + curInterface);
    return false;
  }

  private boolean isWifi () {
    return curInterface == INTERFACE_HUB_WIFI;
  }

  public void startDataTransfer() {
    if (isPortOpen()) {
      hub.sendFlow(hub.TCP_ACTION_START);
      println("Nexus: startDataTransfer(): writing start stream to the nexus device shield...");
    } else {
      println("port not open");
    }
  }

  public void stopDataTransfer() {
    if (isPortOpen()) {
      hub.changeState(hub.STATE_STOPPED);  // make sure it's now interpretting as binary
      hub.sendFlow(hub.TCP_ACTION_STOP);
      println("Nexus: stopDataTransfer(): writing stop stream to the nexus device shield...");
    }
  }

  private int nDataValuesInPacket = 0;
  private int localByteCounter=0;
  private int localChannelCounter=0;
  private int PACKET_readstate = 0;
  // byte[] localByteBuffer = {0,0,0,0};
  private byte[] localAdsByteBuffer = {0, 0, 0};
  private byte[] localAccelByteBuffer = {0, 0};

  private boolean isPortOpen() {
    if (isWifi() || isSerial()) {
      return hub.isPortOpen();
    } else {
      return false;
    }
  }


  //activate or deactivate an EEG channel...channel counting is zero through nchan-1
  public void changeChannelState(int Ichan, boolean activate) {
    if (isPortOpen()) {
      // if ((Ichan >= 0) && (Ichan < command_activate_channel.length)) {
      if ((Ichan >= 0)) {
        if (activate) {
          // write(command_activate_channel[Ichan]);
          // gui.cc.powerUpChannel(Ichan);
          w_timeSeries.hsc.powerUpChannel(Ichan);
        } else {
          // write(command_deactivate_channel[Ichan]);
          // gui.cc.powerDownChannel(Ichan);
          w_timeSeries.hsc.powerDownChannel(Ichan);
        }
      }
    }
  }

  //return the state
  public boolean isStateNormal() {
    if (hub.get_state() == hub.STATE_NORMAL) {
      return true;
    } else {
      return false;
    }
  }

  private int copyRawDataToFullData() {
    //Prior to the 16-chan OpenBCI, we did NOT have rawReceivedDataPacket along with dataPacket...we just had dataPacket.
    //With the 16-chan OpenBCI, where the first 8 channels are sent and then the second 8 channels are sent, we introduced
    //this extra structure so that we could alternate between them.
    //
    //This function here decides how to join the latest data (rawReceivedDataPacket) into the full dataPacket

    if (dataPacket.values.length < 2*rawReceivedDataPacket.values.length) {
      //this is an 8 channel board, so simply copy the data
      return rawReceivedDataPacket.copyTo(dataPacket);
    } else {
      //this is 16-channels, so copy the raw data into the correct channels of the new data
      int offsetInd_values = 0;  //this is correct assuming we just recevied a  "board" packet (ie, channels 1-8)
      int offsetInd_aux = 0;     //this is correct assuming we just recevied a  "board" packet (ie, channels 1-8)
      if (rawReceivedDataPacket.sampleIndex % 2 == 0) { // even data packets are from the daisy board
        offsetInd_values = rawReceivedDataPacket.values.length;  //start copying to the 8th slot
        //offsetInd_aux = rawReceivedDataPacket.auxValues.length;  //start copying to the 3rd slot
        offsetInd_aux = 0;
      }
      return rawReceivedDataPacket.copyTo(dataPacket, offsetInd_values, offsetInd_aux);
    }
  }

  public int copyDataPacketTo(DataPacket_ADS1299 target) {
    return dataPacket.copyTo(target);
  }


  private long timeOfLastChannelWrite = 0;
  private int channelWriteCounter = 0;
  private boolean isWritingChannel = false;

  public void configureAllChannelsToDefault() {
    write('d');
  };

  public void initChannelWrite(int _numChannel) {  //numChannel counts from zero
    timeOfLastChannelWrite = millis();
    isWritingChannel = true;
  }

  public void syncChannelSettings() {
    write("r,start" + hub.TCP_STOP);
  }

  /**
   * Used to convert a gain from the hub back into local codes.
   */
  public char getCommandForGain(int gain) {
    switch (gain) {
      case 1:
        return '0';
      case 2:
        return '1';
      case 4:
        return '2';
      case 6:
        return '3';
      case 8:
        return '4';
      case 12:
        return '5';
      case 24:
      default:
        return '6';
    }
  }

  /**
   * Used to convert raw code to hub code
   * @param inputType {String} - The input from a hub sync channel with register settings
   */
  public char getCommandForInputType(String inputType) {
    if (inputType.equals("normal")) return '0';
    if (inputType.equals("shorted")) return '1';
    if (inputType.equals("biasMethod")) return '2';
    if (inputType.equals("mvdd")) return '3';
    if (inputType.equals("temp")) return '4';
    if (inputType.equals("testsig")) return '5';
    if (inputType.equals("biasDrp")) return '6';
    if (inputType.equals("biasDrn")) return '7';
    return '0';
  }

  /**
   * Used to convert a local channel code into a hub gain which is human
   *  readable and in scientific values.
   */
  public int getGainForCommand(char cmd) {
    switch (cmd) {
      case '0':
        return 1;
      case '1':
        return 2;
      case '2':
        return 4;
      case '3':
        return 6;
      case '4':
        return 8;
      case '5':
        return 12;
      case '6':
      default:
        return 24;
    }
  }

  /**
   * Used right before a channel setting command is sent to the hub to convert
   *  local values into the expected form for the hub.
   */
  public String getInputTypeForCommand(char cmd) {
    final String inputTypeShorted = "shorted";
    final String inputTypeBiasMethod = "biasMethod";
    final String inputTypeMvdd = "mvdd";
    final String inputTypeTemp = "temp";
    final String inputTypeTestsig = "testsig";
    final String inputTypeBiasDrp = "biasDrp";
    final String inputTypeBiasDrn = "biasDrn";
    final String inputTypeNormal = "normal";
    switch (cmd) {
      case '1':
        return inputTypeShorted;
      case '2':
        return inputTypeBiasMethod;
      case '3':
        return inputTypeMvdd;
      case '4':
        return inputTypeTemp;
      case '5':
        return inputTypeTestsig;
      case '6':
        return inputTypeBiasDrp;
      case '7':
        return inputTypeBiasDrn;
      case '0':
      default:
        return inputTypeNormal;
    }
  }

  /**
   * Used to convert a local index number to a hub human readable sd setting
   *  command.
   */
  public String getSDSettingForSetting(int setting) {
    switch (setting) {
      case 1:
        return "5min";
      case 2:
        return "15min";
      case 3:
        return "30min";
      case 4:
        return "1hour";
      case 5:
        return "2hour";
      case 6:
        return "4hour";
      case 7:
        return "12hour";
      case 8:
        return "24hour";
      default:
        return "";
    }
  }

  // FULL DISCLAIMER: this method is messy....... very messy... we had to brute force a firmware miscue
  public void writeChannelSettings(int _numChannel, char[][] channelSettingValues) {   //numChannel counts from zero
    String output = "r,set,";
    output += Integer.toString(_numChannel) + ","; // 0 indexed channel number
    output += channelSettingValues[_numChannel][0] + ","; // power down
    output += getGainForCommand(channelSettingValues[_numChannel][1]) + ","; // gain
    output += getInputTypeForCommand(channelSettingValues[_numChannel][2]) + ",";
    output += channelSettingValues[_numChannel][3] + ",";
    output += channelSettingValues[_numChannel][4] + ",";
    output += channelSettingValues[_numChannel][5] + hub.TCP_STOP;
    write(output);
    // verbosePrint("done writing channel.");
    isWritingChannel = false;
  }

  private long timeOfLastImpWrite = 0;
  private int impWriteCounter = 0;
  private boolean isWritingImp = false;
  public boolean get_isWritingImp() {
    return isWritingImp;
  }

  // public void initImpWrite(int _numChannel) {  //numChannel counts from zero
  //   timeOfLastImpWrite = millis();
  //   isWritingImp = true;
  // }

  public void writeImpedanceSettings(int _numChannel, char[][] impedanceCheckValues) {  //numChannel counts from zero
    String output = "i,set,";
    if (_numChannel < 8) {
      output += (char)('0'+(_numChannel+1)) + ",";
    } else { //(_numChannel >= 8) {
      //command_activate_channel holds non-daisy and daisy values
      output += command_activate_channel[_numChannel] + ",";
    }
    output += impedanceCheckValues[_numChannel][0] + ",";
    output += impedanceCheckValues[_numChannel][1] + hub.TCP_STOP;
    write(output);
    isWritingImp = false;
  }
};
