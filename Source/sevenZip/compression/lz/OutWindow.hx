package sevenZip.compression.lz;

import haxe.io.Bytes;
import haxe.io.Output;

class OutWindow {
    private var _buffer:Bytes;
    private var _pos:Int;
    private var _windowSize:Int = 0;
    private var _streamPos:Int;
    private var _stream:Output;
    
    public function new() {}
    
    public function create(windowSize:Int):Void {
        if (_buffer == null || _windowSize != windowSize)
            _buffer = Bytes.alloc(windowSize);
        _windowSize = windowSize;
        _pos = 0;
        _streamPos = 0;
    }
    
    public function setStream(stream:Output):Void {
        releaseStream();
        _stream = stream;
    }
    
    public function releaseStream():Void {
        flush();
        _stream = null;
    }
    
    public function init(solid:Bool):Void {
        if (!solid) {
            _streamPos = 0;
            _pos = 0;
        }
    }
    
    public function flush():Void {
        var size:Int = _pos - _streamPos;
        if (size == 0)
            return;
        _stream.writeBytes(_buffer, _streamPos, size);
        if (_pos >= _windowSize)
            _pos = 0;
        _streamPos = _pos;
    }
    
    public function copyBlock(distance:Int, len:Int):Void {
		var pos:Int = _pos - distance - 1;
		if (pos < 0)
			pos += _windowSize;
		while (len != 0) {
			if (pos >= _windowSize)
				pos = 0;
			_buffer.set(_pos++, _buffer.get(pos++));
			if (_pos >= _windowSize)
				flush();
			len--;
		}
	}

    
    public function putByte(b:Int):Void {
		_buffer.set(_pos++, b);
		if (_pos >= _windowSize)
			flush();
	}

	public function getByte(distance:Int):Int {
		var pos:Int = _pos - distance - 1;
		if (pos < 0)
			pos += _windowSize;
		return _buffer.get(pos);
	}

}