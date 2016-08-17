///////////////////////////////////////////////////////////////////////////////
//
// This class configures and manages the connection to the OpenBCI Ganglion.
// The connection is implemented via a UDP connection to a UDP port.
// The Gagnlion is configured using single letter text commands sent from the
// PC to the UDP server.  The EEG data streams back from the Ganglion, to the
// UDP server and back to the PC continuously (once started).
//
// Created: AJ Keller, August 2016
//
/////////////////////////////////////////////////////////////////////////////

// import java.io.OutputStream; //for logging raw bytes to an output file

//------------------------------------------------------------------------
//                       Global Functions
//------------------------------------------------------------------------

// println("GanglionSync: parent" + parent);

class OpenBCI_Ganglion {
  final static String UDP_CMD_CONNECT = "c";
  final static String UDP_CMD_COMMAND = "k";
  final static String UDP_CMD_DISCONNECT = "d";
  final static String UDP_CMD_DATA= "t";
  final static String UDP_CMD_ERROR = "e";
  final static String UDP_CMD_SCAN = "s";
  final static String UDP_CMD_STATUS = "q";

  final static byte BYTE_START = (byte)0xA0;
  final static byte BYTE_END = (byte)0xC0;

  // States For Syncing with the hardware
  final static int STATE_NOCOM = 0;
  final static int STATE_COMINIT = 1;
  final static int STATE_SYNCWITHHARDWARE = 2;
  final static int STATE_NORMAL = 3;
  final static int STATE_STOPPED = 4;
  final static int COM_INIT_MSEC = 3000; //you may need to vary this for your computer or your Arduino

  final static int RESP_SUCCESS = 200;
  final static int RESP_ERROR_BAD_PACKET = 500;

  private int state = STATE_NOCOM;
  int prevState_millis = 0; // Used for calculating connect time out

  private int nEEGValuesPerPacket = 4; // Defined by the data format sent by openBCI boards
  private int nAuxValuesPerPacket = 0; // Defined by the arduino code

  private int udpGanglionPortRx = 10997;
  private int udpGanglionPortTx = 10996;
  private String udpGanglionIP = "localhost";

  private final float fs_Hz = 256.0f;  //sample rate used by OpenBCI Ganglion board... set by its Arduino code
  private final float MCP3912_Vref = 1.2f;  // reference voltage for ADC in MCP3912 set in hardware
  private float MCP3912_gain = 1.0;  //assumed gain setting for MCP3912.  NEEDS TO BE ADJUSTABLE JM
  private float scale_fac_uVolts_per_count = (MCP3912_Vref * 1000000.f) / (8388607.0 * MCP3912_gain * 1.5 * 51.0); //MCP3912 datasheet page 34. Gain of InAmp = 80
  // private final float scale_fac_accel_G_per_count = 0.002 / ((float)pow(2,4));  //assume set to +/4G, so 2 mG per digit (datasheet). Account for 4 bits unused
  // private final float leadOffDrive_amps = 6.0e-9;  //6 nA, set by its Arduino code

  private int bleErrorCounter = 0;
  private int prevSampleIndex = 0;

  private DataPacket_ADS1299 dataPacket;

  //here is the serial port for this OpenBCI board
  public UDPReceive udpRx = null;
  private UDPSend udpTx = null;
  private boolean portIsOpen = false;
  private boolean connected = false;

  public String[] deviceList = new String[0];
  public int numberOfDevices = 0;

  // Getters
  public float get_fs_Hz() { return fs_Hz; }
  public boolean isPortOpen() { return portIsOpen; }
  public float get_scale_fac_uVolts_per_count() { return scale_fac_uVolts_per_count; }

  //constructors
  OpenBCI_Ganglion() {};  //only use this if you simply want access to some of the constants
  OpenBCI_Ganglion(PApplet applet) {

    // Initialize UDP ports
    udpRx = new UDPReceive(applet, udpGanglionPortRx, udpGanglionIP);
    udpTx = new UDPSend(udpGanglionPortTx, udpGanglionIP);

    // For storing data into
    dataPacket = new DataPacket_ADS1299(nEEGValuesPerPacket,nAuxValuesPerPacket);  //this should always be 8 channels
    for(int i = 0; i < nEEGValuesPerPacket; i++) {
      dataPacket.values[i] = 0;
    }
    for(int i = 0; i < nAuxValuesPerPacket; i++){
      dataPacket.auxValues[i] = 0;
    }
  }

  // Return true if the display needs to be updated for the BLE list
  public boolean parseMessage(String msg) {
    String[] list = split(msg, ',');
    int index = 0;
    switch (list[0].charAt(0)) {
      case 'c': // Connect
        if (isSuccessCode(Integer.parseInt(list[1]))) {
          println("OpenBCI_Ganglion: parseMessage: connect: success!");
          output("OpenBCI_Ganglion: The GUI is done intializing. Click outside of the control panel to interact with the GUI.");
          systemMode = 10;
          connected = true;
        } else {
          println("OpenBCI_Ganglion: parseMessage: connect: failure :(");
          output("Unable to connect to ganglion!");
          connected = false;
        }
        return false;
      case 't': // Data
        if (isSuccessCode(Integer.parseInt(list[1]))) {
          // Sample number stuff
          dataPacket.sampleIndex = int(Integer.parseInt(list[2]));
          if ((dataPacket.sampleIndex - prevSampleIndex) != 1) {
            if(dataPacket.sampleIndex != 0){  // if we rolled over, don't count as error
              bleErrorCounter++;
              println("OpenBCI_Ganglion: apparent sampleIndex jump from Serial data: " + prevSampleIndex + " to  " + dataPacket.sampleIndex + ".  Keeping packet. (" + bleErrorCounter + ")");
            }
          }
          prevSampleIndex = dataPacket.sampleIndex;

          // Channel data storage
          for (int i = 0; i < 4; i++) {
            dataPacket.values[i] = Integer.parseInt(list[3 + i]);
          }
          curDataPacketInd = (curDataPacketInd+1) % dataPacketBuff.length; //this is also used to let the rest of the code that it may be time to do something
          ganglion.copyDataPacketTo(dataPacketBuff[curDataPacketInd]);  //resets isNewDataPacketAvailable to false
          newPacketCounter++;
        } else {
          bleErrorCounter++;
          println("OpenBCI_Ganglion: parseMessage: data: bad");
        }
        return false;
      case 'e': // Error
        println("OpenBCI_Ganglion: parseMessage: error: " + list[2]);
        return false;
      case 's': // Scan
        this.deviceList = new String[list.length - 3];
        for (int i = 2; i < (list.length - 1); i++) {
          // Last element has the stop command
          this.deviceList[index] = list[i];
          index++;
        }
        return true;
      default:
        println("OpenBCI_Ganglion: parseMessage: default: " + msg);
        return false;
    }
  }

  public int copyDataPacketTo(DataPacket_ADS1299 target) {
    return dataPacket.copyTo(target);
  }

  public boolean isSuccessCode(int c) {
    return c == RESP_SUCCESS;
  }

  public void getBLEDevices() {
    deviceList = null;
    udpTx.send(UDP_CMD_SCAN);
  }

  public void connectBLE(String id) {
    udpTx.send(UDP_CMD_CONNECT + "," + id);
  }

  public void disconnectBLE() {
    udpTx.send(UDP_CMD_DISCONNECT);
  }

  public void updateSyncState() {
    //has it been 3000 milliseconds since we initiated the serial port? We want to make sure we wait for the OpenBCI board to finish its setup()
    if ((millis() - prevState_millis > COM_INIT_MSEC) && (prevState_millis != 0) && (state == openBCI.STATE_COMINIT) ) {
      // We are synced and ready to go!
      state = STATE_SYNCWITHHARDWARE;
      println("OpenBCI_Ganglion: Sending reset command");
      // serial_openBCI.write('v');
    }
  }

  /**
   * @description Sends a start streaming command to the Ganglion Node module.
   */
  void startDataTransfer(){
    changeState(STATE_NORMAL);  // make sure it's now interpretting as binary
    println("OpenBCI_Ganglion: startDataTransfer(): sending \'" + command_startBinary);
    udpTx.send(UDP_CMD_COMMAND + "," + command_startBinary);
  }

  /**
   * @description Sends a stop streaming command to the Ganglion Node module.
   */
  public void stopDataTransfer() {
    changeState(STATE_STOPPED);  // make sure it's now interpretting as binary
    println("OpenBCI_Ganglion: stopDataTransfer(): sending \'" + command_stop);
    udpTx.send(UDP_CMD_COMMAND + "," + command_stop);
  }

  private void printGanglion(String msg) {
    print("OpenBCI_Ganglion: "); println(msg);
  }

  public int changeState(int newState) {
    state = newState;
    prevState_millis = millis();
    return 0;
  }

  // Channel setting
  //activate or deactivate an EEG channel...channel counting is zero through nchan-1
  public void changeChannelState(int Ichan, boolean activate) {
    if (connected) {
      // if ((Ichan >= 0) && (Ichan < command_activate_channel.length)) {
      if ((Ichan >= 0)) {
        if (activate) {
          // serial_openBCI.write(command_activate_channel[Ichan]);
          gui.cc.powerUpChannel(Ichan);
        } else {
          // serial_openBCI.write(command_deactivate_channel[Ichan]);
          gui.cc.powerDownChannel(Ichan);
        }
      }
    }
  }
};
