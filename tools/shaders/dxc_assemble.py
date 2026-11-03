import ctypes as C
import uuid
from pathlib import Path

P=C.c_void_p;U=C.c_uint32;H=C.c_int32
class GUID(C.Structure):
    _fields_=[('raw',C.c_ubyte*16)]
    def __init__(self,text):super().__init__((C.c_ubyte*16).from_buffer_copy(uuid.UUID(text).bytes_le))
def check(v):
    if v<0:raise RuntimeError(f'HRESULT {v&0xffffffff:08x}')
def method(obj,index,ret,args):
    table=C.cast(obj,C.POINTER(C.POINTER(P))).contents
    return C.WINFUNCTYPE(ret,P,*args)(table[index])
def blob_bytes(blob):
    return C.string_at(method(blob,3,P,[])(blob),method(blob,4,C.c_size_t,[])(blob)) if blob else b''
class Assembler:
    def __init__(self, dll):
        self.dll=C.WinDLL(str(Path(dll).resolve()))
        self.create=self.dll.DxcCreateInstance
        self.create.argtypes=[C.POINTER(GUID),C.POINTER(GUID),C.POINTER(P)];self.create.restype=H
        self.library=self.instance('6245d6af-66e0-48fd-80b4-4d271796748c','e5204dc7-d18c-4c3c-bdfb-851673980fe7')
        self.assembler=self.instance('d728db68-f903-4f80-94cd-dccf76ec7151','091f7a26-1c1f-4948-904b-e6e3a8a771d5')
        self.validator=self.instance('8ca3e215-f728-4cf3-8cdd-88af917587a1','a6e82bd2-1fd7-4826-9811-2857e797f49a')
    def instance(self,cls,iid):
        obj=P();check(self.create(C.byref(GUID(cls)),C.byref(GUID(iid)),C.byref(obj)));return obj
    def result(self,op):
        status=H();check(method(op,3,H,[C.POINTER(H)])(op,C.byref(status)))
        err=P();check(method(op,5,H,[C.POINTER(P)])(op,C.byref(err)))
        message=blob_bytes(err).decode('utf8',errors='replace')
        if status.value<0:raise RuntimeError(f'{status.value&0xffffffff:08x}: {message}')
        result=P();check(method(op,4,H,[C.POINTER(P)])(op,C.byref(result)));return result
    def assemble(self,text):
        source=text.encode('utf8');buffer=C.create_string_buffer(source);blob=P()
        check(method(self.library,6,H,[P,U,U,C.POINTER(P)])(self.library,buffer,len(source),65001,C.byref(blob)))
        op=P();check(method(self.assembler,3,H,[P,C.POINTER(P)])(self.assembler,blob,C.byref(op)))
        result=self.result(op)
        validated=P();check(method(self.validator,3,H,[P,U,C.POINTER(P)])(self.validator,result,1,C.byref(validated)))
        self.result(validated)
        output=blob_bytes(result)
        for obj in (blob,op,result,validated):method(obj,2,U,[])(obj)
        return output
    def validate(self,data):
        buffer=C.create_string_buffer(data);blob=P();op=P()
        check(method(self.library,6,H,[P,U,U,C.POINTER(P)])(self.library,buffer,len(data),0,C.byref(blob)))
        check(method(self.validator,3,H,[P,U,C.POINTER(P)])(self.validator,blob,0,C.byref(op)))
        result=self.result(op)
        for obj in (result,op,blob):method(obj,2,U,[])(obj)

