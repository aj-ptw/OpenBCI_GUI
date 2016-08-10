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

class OpenBCI_Ganglion {
  final static byte BYTE_START = (byte)0xA0;
  final static byte BYTE_END = (byte)0xC0;

  //constructors
  OpenBCI_Ganglion() {};  //only use this if you simply want access to some of the constants
  OpenBCI_Ganglion(PApplet applet, String uuid) {
    printGanglion("starting");

    connectUDP(applet, uuid);
  }

  private void connectUDP(PApplet applet, String uuid) {
    printGanglion("connected to UDP with uuid: " + uuid);
    systemMode = 10;
  }

  private void disconnectBLE() {

  }

  private void printGanglion(String msg) {
    print("OpenBCI_Ganglion: "); println(msg);
  }
};
