import zlib, struct
W,H=400,300
raw=b"".join(b"\x00"+bytes(v for x in range(W) for v in ((x*255)//W,(y*255)//H,128)) for y in range(H))
def chunk(t,d): 
    c=t+d; return struct.pack(">I",len(d))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",W,H,8,2,0,0,0))+chunk(b"IDAT",zlib.compress(raw,6))+chunk(b"IEND",b"")
open("sample.png","wb").write(png)
print(len(png))
