#include <Array.au3> ; For _ArrayToString function
#include <FileConstants.au3>
#include <File.au3>

;RECEIVER SENDER
Global $myState="RECEIVER"

;NEUTRAL BUSY
Global $dataLinkState="NEUTRAL"

;INSTRUMENT LAB
Global $computerType="INSTRUMENT"

Global $enqChar = Chr(5)
Global $akChar = Chr(6)
Global $nakChar = Chr(21)
Global $stxChar = Chr(2)
Global $etbChar = Chr(23)
Global $canChar = Chr(24)
Global $etxChar = Chr(3)
Global $eotChar = Chr(4)


; Initialize the TCP library
TCPStartup()

; Create a listening socket on a specific port (e.g., port 12345)
Global $port = 5051
Global $socket = TCPListen("0.0.0.0", $port)
Global $clientSocket


; Check for errors in creating the socket
If $socket = -1 Then
    MsgBox(16, "Error", "Failed to create listening socket. Error: " & @error)
    Exit
EndIf

; Main server loop
While True
    ; Wait for a client to connect
    $clientSocket = TCPAccept($socket)

    ; Check if a client has connected
    If $clientSocket <> -1 Then
		WriteToLogFile("Client connected...")

		Inconnection()
    EndIf

    ; Sleep to avoid high CPU usage
    Sleep(100)
WEnd


Func Inconnection()
	While True
	; Read data from the client
        $data = TCPRecv($clientSocket, 6000)

        ; Check if data was received
        If Not @error and  $data <>"" Then
            ; Display received data
            TrayTip("Information", "Received data", 5)
			WriteToLogFile("Received data: "&$data)

            ; Echo the data back to the client
            ;TCPSend($clientSocket, $data)

			ProcessTheDataReceived($data)
        EndIf

        ; Close the client socket
        ;TCPCloseSocket($clientSocket)
	WEnd
EndFunc

; Cleanup and shutdown
TCPShutdown()

Func WriteToLogFile($message)
    Local $logFilePath = @ScriptDir & "\log.txt"

    ; Create or open the log file and its path if they do not exist
    Local $fileHandle = FileOpen($logFilePath, $FO_APPEND + $FO_CREATEPATH)

    If $fileHandle = -1 Then
        MsgBox($MB_SYSTEMMODAL, "Error", "Unable to open or create the log file.")
        Return
    EndIf

    Local $timestamp = @YEAR & "/" & @MON & "/" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC
    FileWriteLine($fileHandle, "[" & $timestamp & "] " & $message)
    FileClose($fileHandle)
EndFunc

Func ProcessTheDataReceived($data)
	WriteToLogFile("processing data: "&$data)
	;client is transmitting
	If StringInStr($data, $stxChar) Then
		WriteToLogFile("client is transmitting: "&$data)
		$dataReceived=ReceiveData()
		WriteToLogFile($dataReceived)
	EndIf

	;client is inquiring
	If StringInStr($data, $enqChar) Then
		WriteToLogFile("Received inquiry: "&$data)
		If $dataLinkState<>"BUSY" Then
			$data=$akChar
			TCPSend($clientSocket, $data)
			WriteToLogFile("acknowleged inquiry")
		Else
			$data=$nakChar
			TCPSend($clientSocket, $data)
			WriteToLogFile("refused inquiry... iam busy")
		EndIf
	EndIf

	$dataLinkState="NEUTRAL"

EndFunc


Func InquieryState()
	Local $receivedData = ""
    Local $timeout = 30 ; Timeout in seconds

    ; Set a timer to prevent waiting indefinitely
    Local $timer = TimerInit()

    While TimerDiff($timer) < ($timeout * 1000)
		WriteToLogFile("waiting for the data link to enter neutral state...")

		if $dataLinkState=="NEUTRAL" Then
			WriteToLogFile("data link now in neutral state")
			WriteToLogFile("entering inquiery state...")
			$data=$enqChar
			TCPSend($clientSocket, $data)
			WriteToLogFile("sent inquiry to client")
			ExitLoop
		EndIf

		sleep(1000)

	WEnd
	Local $receivedData = ""
    Local $timeout = 30 ; Timeout in seconds

    ; Set a timer to prevent waiting indefinitely
    Local $timer = TimerInit()

    While TimerDiff($timer) < ($timeout * 1000)

		WriteToLogFile("waiting for response to inquiry...")
        ; Read data from the client
        $data = TCPRecv($clientSocket, 1024)

        ; Check if data was received
        If Not @error Then
            ; Display received data
            TrayTip("Information", "Received data", 5)
			WriteToLogFile("Received data: "&$data)

			If StringInStr($data, $akChar) Then
				TransferPhase('P|1|')
			EndIf

			If StringInStr($data, $nakChar) Then
				sleep(10000)
				$data=$enqChar
				TCPSend($clientSocket, $data)
			EndIf

			If StringInStr($data, $enqChar) Then
				if $computerType="INSTRUMENT" Then
					sleep(1000)
					$data=$enqChar
					TCPSend($clientSocket, $data)
				EndIf

				if $computerType="LAB" Then
					$dataLinkState="NEUTRAL"
					;ReceiveMessage()
				EndIf
			EndIf



        Else

			WriteToLogFile("no reply to inquiry yet..."&@error)
			;ExitLoop

		EndIf

	WEnd
EndFunc


Func TransferPhase($message)
    Local $frameNumber = 0
    Local $frameSize = 64000
    Local $checksum = 0

    ; Split the message into frames and send them
    While $message <> ""
        $frameNumber = ($frameNumber + 1)
        If $frameNumber > 7 Then
            $frameNumber = 0
        EndIf

		; Encode the message in UTF-8
        $encodedMessage = StringToUTF8(StringLeft($message, $frameSize))

        $frame = $stxChar & $frameNumber & StringLeft($encodedMessage, $frameSize) & $etbChar & CalculateChecksum($message) & @CRLF

        ; Send the frame
        TCPSend($clientSocket, $frame)
        ConsoleWrite("Sender: Sent frame #" & $frameNumber & @CRLF)

        ; Wait for and handle acknowledgment frame
        Local $acknowledgment = WaitForAcknowledgment($frameNumber)

        If $acknowledgment = $akChar Then
            ConsoleWrite("Sender: Received <ACK> for frame #" & $frameNumber & @CRLF)
            $message = StringTrimLeft($message, $frameSize)
        ElseIf $acknowledgment = $nakChar Then
            ConsoleWrite("Sender: Received <NAK> for frame #" & $frameNumber & ". Retransmitting..." & @CRLF)
            RetransmitFrame($frame)
        Else
            ConsoleWrite("Sender: Received unexpected response for frame #" & $frameNumber & ". Retransmitting..." & @CRLF)
            RetransmitFrame($frame)
        EndIf
    WEnd

    ; Send an end frame
    $frameNumber = ($frameNumber + 1)
    If $frameNumber > 7 Then
        $frameNumber = 0
    EndIf

	; Encode an empty message for the end frame
    $encodedEndFrameMessage = StringToUTF8("")
	$frame = $stxChar & $frameNumber & $encodedEndFrameMessage & $eotChar & CalculateChecksum($encodedEndFrameMessage) & @CRLF
    TCPSend($clientSocket, $frame)
    TCPSend($clientSocket, $frame)
    ConsoleWrite("Sender: Sent end frame #" & $frameNumber & @CRLF)

    ; Wait for and handle acknowledgment frame for the end frame
    Local $endFrameAcknowledgment = WaitForAcknowledgment($frameNumber)

    If $endFrameAcknowledgment = $akChar Then
        ConsoleWrite("Sender: Received <ACK> for end frame #" & $frameNumber & @CRLF)
    ElseIf $endFrameAcknowledgment = $nakChar Then
        ConsoleWrite("Sender: Received <NAK> for end frame #" & $frameNumber & ". Retransmitting..." & @CRLF)
        RetransmitFrame($frame)
    Else
        ConsoleWrite("Sender: Received unexpected response for end frame #" & $frameNumber & ". Retransmitting..." & @CRLF)
        RetransmitFrame($frame)
    EndIf
EndFunc

Func RetransmitFrame($frame)
    TCPSend($clientSocket, $frame)
    ConsoleWrite("Retransmitted frame: " & $frame & @CRLF)
EndFunc


Func WaitForAcknowledgment($expectedFrameNumber)
    Local $timeout = 15 ; Timeout in seconds

    ; Set a timer to prevent waiting indefinitely
    Local $timer = TimerInit()

    While TimerDiff($timer) < ($timeout * 1000)
        $response = TCPRecv($clientSocket, 1024)

        ; Check if the response is an acknowledgment frame
        If $response = $akChar Or $response = $nakChar Then
            ; Extract the frame number from the acknowledgment frame
            Local $ackFrameNumber = Number(StringMid($response, 2, 1))

            ; Check if the acknowledgment frame matches the expected frame number
            If $ackFrameNumber = $expectedFrameNumber Then
                Return $response ; Return the acknowledgment type
            EndIf
        EndIf
    WEnd

    ; Timed out, no acknowledgment received
    Return ""
EndFunc

Func ReceiveData()
	While True
		$response = TCPRecv($clientSocket, 1024)
		if $response<>"" Then
			ConsoleWrite($response&@CRLF)
			TCPSend($clientSocket, $akChar)
		EndIf
		TCPSend($clientSocket, $akChar)
		ConsoleWrite($response&@CRLF)
	WEnd
EndFunc


Func ReceiveData0()
	ConsoleWrite("entering receive mode"& @CRLF)
    Local $receivedData = ""
    Local $timeout = 30 ; Timeout in seconds

    ; Set a timer to prevent waiting indefinitely
    Local $timer = TimerInit()

    While TimerDiff($timer) < ($timeout * 1000)
        $response = TCPRecv($clientSocket, 1024)

        ; Check for an end frame or intermediate frame
        If StringInStr($response, $eotChar) Then
			ConsoleWrite("received end frame"& @CRLF)
            ; Process the end frame
            If ValidateFrame($response, "end") Then
				ConsoleWrite("Received valid frame"& @CRLF)
                $receivedData &= StringStripWS(StringLeft($response, StringInStr($response, $eotChar) - 1), 3)

                ; Send an <ACK> response for the end frame
                TCPSend($clientSocket, $akChar)
            Else
                ; Send a <NAK> response for an invalid end frame
                TCPSend($clientSocket, $nakChar)
				ConsoleWrite("Received invalid frame requested for retransmission"& @CRLF)
            EndIf

            ExitLoop
        ElseIf StringInStr($response, $etbChar) Then
			ConsoleWrite("received intermediate frame"& @CRLF)
            ; Process an intermediate frame
            If ValidateFrame($response, "intermediate") Then
				ConsoleWrite("received valid frame"& @CRLF)
                $receivedData &= StringStripWS(StringLeft($response, StringInStr($response, $etbChar) - 1), 3)

                ; Send an <ACK> response for the intermediate frame
                TCPSend($clientSocket, $akChar)
            Else
				ConsoleWrite("received invalid frame requested for a resend"& @CRLF)
                ; Send a <NAK> response for an invalid intermediate frame
                TCPSend($clientSocket, $nakChar)
            EndIf
        Else
            ConsoleWrite("received totally invalid frame"& @CRLF)
			; Invalid frame, send <NAK> response
            TCPSend($clientSocket, $nakChar)
        EndIf
    WEnd

    Return $receivedData
EndFunc

Func ValidateFrame($frame, $type)
	Return True
    ; Check if the frame starts with <STX> and ends with <ETB> or <ETX>
    If $type = "intermediate" Then
        If StringLeft($frame, 1) <> $stxChar Or StringRight($frame, 4) <> $etbChar & CalculateChecksum(StringMid($frame, 2, StringLen($frame) - 5)) & @CRLF Then
            Return False
        EndIf
    ElseIf $type = "end" Then
        If StringLeft($frame, 1) <> $stxChar Or StringRight($frame, 4) <> $eotChar & CalculateChecksum("") & @CRLF Then
            Return False
        EndIf
    Else
        ; Invalid frame type
        Return False
    EndIf

    ; Extract the frame number from the frame
    Local $frameNumber = Number(StringMid($frame, 2, 1))

    ; Check if the frame number is as expected (within the range 0-7)
    If $frameNumber < 0 Or $frameNumber > 7 Then
        Return False
    EndIf

    ; Calculate the expected checksum
    Local $expectedChecksum = CalculateChecksum(StringMid($frame, 2, StringLen($frame) - 5))

    ; Extract the received checksum from the frame
    Local $receivedChecksum = StringMid($frame, StringLen($frame) - 3, 2)

    ; Compare the received checksum with the expected checksum
    If $receivedChecksum <> $expectedChecksum Then
        Return False
    EndIf

    ; Frame passed all validation checks
    Return True
EndFunc

Func CalculateChecksum($text)
    Local $checksum = 0

    ; Calculate checksum for the given text
    For $i = 1 To StringLen($text)
        $checksum += Asc(StringMid($text, $i, 1))
    Next

    ; Keep the least significant eight bits
    $checksum = Mod($checksum, 256)

    ; Convert checksum to two ASCII characters
    Local $checksumChar1 = Chr(Int($checksum / 16) + Asc("0"))
    Local $checksumChar2 = Chr(Mod($checksum, 16) + Asc("0"))

    Return $checksumChar1 & $checksumChar2
EndFunc

Func StringToUTF8($str)
	Return $str
    Local $utf8 = BinaryToString(StringToBinary($str, 4), 1)
    Return $utf8
EndFunc