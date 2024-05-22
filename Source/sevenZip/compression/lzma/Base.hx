package sevenZip.compression.lzma;

class Base {
    public static inline var kNumRepDistances:Int = 4;
    public static inline var kNumStates:Int = 12;
    
    public static function stateInit():Int {
        return 0;
    }
    
    public static function stateUpdateChar(index:Int):Int {
        if (index < 4) return 0;
        if (index < 10) return index - 3;
        return index - 6;
    }
    
    public static function stateUpdateMatch(index:Int):Int {
        return (index < 7 ? 7 : 10); 
    }

    public static function stateUpdateRep(index:Int):Int { 
        return (index < 7 ? 8 : 11); 
    }
    
    public static function stateUpdateShortRep(index:Int):Int { 
        return (index < 7 ? 9 : 11); 
    }

    public static function stateIsCharState(index:Int):Bool { 
        return index < 7; 
    }
    
    public static inline var kNumPosSlotBits:Int = 6;
    public static inline var kDicLogSizeMin:Int = 0;
    // public static inline var kDicLogSizeMax:Int = 28;
    // public static inline var kDistTableSizeMax:Int = kDicLogSizeMax * 2;
    
    public static inline var kNumLenToPosStatesBits:Int = 2; // it's for speed optimization
    public static inline var kNumLenToPosStates:Int = 1 << kNumLenToPosStatesBits;
    
    public static inline var kMatchMinLen:Int = 2;
    
    public static function getLenToPosState(len:Int):Int {
        len -= kMatchMinLen;
        if (len < kNumLenToPosStates)
            return len;
        return kNumLenToPosStates - 1;
    }
    
    public static inline var kNumAlignBits:Int = 4;
    public static inline var kAlignTableSize:Int = 1 << kNumAlignBits;
    public static inline var kAlignMask:Int = (kAlignTableSize - 1);
    
    public static inline var kStartPosModelIndex:Int = 4;
    public static inline var kEndPosModelIndex:Int = 14;
    public static inline var kNumPosModels:Int = kEndPosModelIndex - kStartPosModelIndex;
    
    public static inline var kNumFullDistances:Int = (1 << Std.int(kEndPosModelIndex / 2));
    
    public static inline var kNumLitPosStatesBitsEncodingMax:Int = 4;
    public static inline var kNumLitContextBitsMax:Int = 8;
    
    public static inline var kNumPosStatesBitsMax:Int = 4;
    public static inline var kNumPosStatesMax:Int = 1 << kNumPosStatesBitsMax;
    public static inline var kNumPosStatesBitsEncodingMax:Int = 4;
    public static inline var kNumPosStatesEncodingMax:Int = 1 << kNumPosStatesBitsEncodingMax;
    
    public static inline var kNumLowLenBits:Int = 3;
    public static inline var kNumMidLenBits:Int = 3;
    public static inline var kNumHighLenBits:Int = 8;
    public static inline var kNumLowLenSymbols:Int = 1 << kNumLowLenBits;
    public static inline var kNumMidLenSymbols:Int = 1 << kNumMidLenBits;
    public static inline var kNumLenSymbols:Int = kNumLowLenSymbols + kNumMidLenSymbols +
            (1 << kNumHighLenBits);
    public static inline var kMatchMaxLen:Int = kMatchMinLen + kNumLenSymbols - 1;
}