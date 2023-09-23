#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.16.1
 Author:         myName

 Script Function:
	Template AutoIt script.

#ce ----------------------------------------------------------------------------

#include <GUIConstantsEx.au3>
#include <MsgBoxConstants.au3>
#include <WinAPIFiles.au3>

Global $SERVER_IP = "127.0.0.1"
Global $SERVER_PORT = 8888

TCPStartup()

; Create a listening socket
Global $serverSocket = TCPListen($SERVER_IP, $SERVER_PORT)
If $serverSocket = -1 Then
    MsgBox($MB_SYSTEMMODAL, "Error", "Error starting the server. Exiting.")
    Exit
EndIf

MsgBox($MB_SYSTEMMODAL, "Server", "Server listening on " & $SERVER_IP & ":" & $SERVER_PORT)

While True
    ; Wait for a client to connect
    Global $clientSocket = TCPAccept($serverSocket)
    If $clientSocket <> -1 Then
        ; A client has connected
        MsgBox($MB_SYSTEMMODAL, "Client Connected", "Client connected from " & TCPNameToIP(TCPRecv($clientSocket, 1024)))

        ; Process client requests (in this example, simply echo back what the client sends)
        While 1
            $data = TCPRecv($clientSocket, 1024)
            If @error Then ExitLoop
            TCPSend($clientSocket, "Server received: " & $data)
        WEnd

        TCPCloseSocket($clientSocket)
        MsgBox($MB_SYSTEMMODAL, "Client Disconnected", "Client disconnected.")
    EndIf
WEnd

TCPShutdown()

