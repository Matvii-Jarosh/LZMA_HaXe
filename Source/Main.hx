package;

import lime.app.Application;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import haxe.crypto.Base64;
import sevenZip.compression.lzma.Encoder;
import sevenZip.compression.lzma.Decoder;
import haxe.Utf8;
import haxe.Int64;


class Main extends Application
{
	public function new()
	{
		super();

		var inputString = "Hello, World!";
		trace("Original text: " + inputString);

        var inputBytes = Bytes.ofString(inputString);
		trace("Original text (Hex): " + bytesToHex(inputBytes));

        var encodedBytes = encodeLZMA(inputBytes);
        trace("Encoded (Hex): " + bytesToHex(encodedBytes));

        var decodedBytes = decodeLZMA(encodedBytes);
        var decodedString = decodedBytes.toString();
        trace("Decoded: " + decodedString);
		//flash.system.System.exit(0);
    }

    public static function encodeLZMA(data:Bytes):Bytes {
        var encoder = new Encoder();
        var outputStream = new BytesOutput();

        encoder.setAlgorithm(2);
        encoder.setDictionarySize(1 << 23);
        encoder.setNumFastBytes(128);
        encoder.setMatchFinder(1);
        encoder.setLcLpPb(3, 0, 2);
        encoder.setEndMarkerMode(false);

        encoder.writeCoderProperties(outputStream);
        var fileSize = data.length;
        for (i in 0...8) {
            outputStream.writeByte((fileSize >> (8 * i)) & 0xFF);
        }

        var inputStream = new BytesInput(data);
        encoder.code(inputStream, outputStream, -1, -1, null);

        return outputStream.getBytes();
    }

    public static function decodeLZMA(data:Bytes):Bytes {
        var decoder = new Decoder();
        var inputStream = new BytesInput(data);
        var outputStream = new BytesOutput();

        var properties = inputStream.read(5);
        if (!decoder.setDecoderProperties(properties)) {
            throw "Incorrect stream properties";
        }

        var outSize:Int64 = Int64.make(0, 0);
        for (i in 0...8) {
            var v = inputStream.readByte();
            outSize = Int64.or(outSize, Int64.shl(Int64.make(v, 0), 8 * i));
        }

        if (!decoder.code(inputStream, outputStream, outSize.low)) {
            throw "Error in data stream";
        }

        return outputStream.getBytes();
    }

    public static function bytesToHex(bytes:Bytes):String {
        var hexChars = "0123456789abcdef";
        var hexString = new StringBuf();

        for (i in 0...bytes.length) {
            var byte = bytes.get(i);
            hexString.add(hexChars.charAt((byte >> 4) & 0xF));
            hexString.add(hexChars.charAt(byte & 0xF));
        }

        return hexString.toString();
    }
	
}