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

import java.io.OutputStream; //for logging raw bytes to an output file

void udpEvent(String msg) {

}

class OpenBCI_Ganglion {
  final static byte UDP_CMD_CONNECT = "c";
  final static byte UDP_CMD_COMMAND = "k";
  final static byte UDP_CMD_DISCONNECT = "d";
  final static byte UDP_CMD_ERROR = "e";
  final static byte UDP_CMD_SCAN = "s";

  final static byte BYTE_START = (byte)0xA0;
  final static byte BYTE_END = (byte)0xC0;

  // States For Syncing with the hardware
  final static int STATE_NOCOM = 0;
  final static int STATE_COMINIT = 1;
  final static int STATE_SYNCWITHHARDWARE = 2;
  final static int STATE_NORMAL = 3;
  final static int STATE_STOPPED = 4;
  final static int COM_INIT_MSEC = 3000; //you may need to vary this for your computer or your Arduino

  private int state = STATE_NOCOM;
  int prevState_millis = 0; // Used for calculating connect time out

  private int nEEGValuesPerPacket = 4; //defined by the data format sent by openBCI boards

  private int udpGanglionPort = 10996;
  private String udpGanglionIP = "localhost";

  //here is the serial port for this OpenBCI board
  private UDPClass udp = null;
  private boolean portIsOpen = false;

  //constructors
  OpenBCI_Ganglion() {};  //only use this if you simply want access to some of the constants
  OpenBCI_Ganglion(PApplet applet, String uuid) {
    printGanglion("starting");

    upd = new UDPClass(applet, udpGanglionPort, udpGanglionIP);

    hardwareSyncStep = 0;
    changeState(STATE_COMINIT);
    syncWithHardware();
  }

  public void syncWithHardware(){
    switch (hardwareSyncStep) {
      case 1:
        println("OpenBCI_Ganglion: syncWithHardware: [1] Sending channel count (" + nchan + ") to OpenBCI...");
        break;
      case 5:

        println("OpenBCI_Ganglion: syncWithHardware: [5] Writing selected SD setting (" + sdSettingString + ") to OpenBCI...");
        break;
      case 6:
        output("OpenBCI_Ganglion: syncWithHardware: The GUI is done intializing. Click outside of the control panel to interact with the GUI.");
        changeState(STATE_STOPPED);
        systemMode = 10;
        //renitialize GUI if nchan has been updated... needs to be built
        break;
    }
  }

  public void updateSyncState() {
    //has it been 3000 milliseconds since we initiated the serial port? We want to make sure we wait for the OpenBCI board to finish its setup()
    if ((millis() - prevState_millis > COM_INIT_MSEC) && (prevState_millis != 0) && (state == openBCI.STATE_COMINIT) ) {
      // We are synced and ready to go!
      state = STATE_SYNCWITHHARDWARE;
      println("OpenBCI_Ganglion: Sending reset command");
      // serial_openBCI.write('v');
    }

    //if we are in SYNC WITH HARDWARE state ... trigger a command
    // if ( (state == STATE_SYNCWITHHARDWARE) && (currentlySyncing == false) ) {
    //   if(millis() - timeOfLastCommand > 200 && readyToSend == true){
    //     timeOfLastCommand = millis();
    //     hardwareSyncStep++;
    //     syncWithHardware(sdSetting);
    //   }
    // }
  }

  void startDataTransfer(){
    if (udp != null) {
      changeState(STATE_NORMAL);  // make sure it's now interpretting as binary
      println("OpenBCI_Ganglion: startDataTransfer(): writing \'" + command_startBinary + "\' to the serial port...");
      serial_openBCI.write(command_startBinary);
    }
  }

  public void stopDataTransfer() {
    if (serial_openBCI != null) {
      serial_openBCI.clear(); // clear anything in the com port's buffer
      openBCI.changeState(STATE_STOPPED);  // make sure it's now interpretting as binary
      println("OpenBCI_Ganglion: startDataTransfer(): writing \'" + command_stop + "\' to the serial port...");
      serial_openBCI.write(command_stop);// + "\n");
    }
  }

  public boolean isSerialPortOpen() {
    if (portIsOpen & (serial_openBCI != null)) {
      return true;
    } else {
      return false;
    }
  }

  private void printGanglion(String msg) {
    print("OpenBCI_Ganglion: "); println(msg);
  }

  public int changeState(int newState) {
    state = newState;
    prevState_millis = millis();
    return 0;
  }
};
