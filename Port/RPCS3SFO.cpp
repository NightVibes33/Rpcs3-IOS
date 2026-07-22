#include "RPCS3SFO.h"
#include <cstdint>
#include <fstream>
#include <sstream>
#include <vector>
namespace rpcs3::ios { namespace {
uint16_t le16(const unsigned char* p){return static_cast<uint16_t>(p[0]|(p[1]<<8));}
uint32_t le32(const unsigned char* p){return static_cast<uint32_t>(p[0])|(static_cast<uint32_t>(p[1])<<8)|(static_cast<uint32_t>(p[2])<<16)|(static_cast<uint32_t>(p[3])<<24);}
bool fits(uint64_t o,uint64_t s,uint64_t n){return o<=n&&s<=n-o;}
std::string text_at(const std::vector<unsigned char>& b,uint32_t off,uint32_t len){if(!fits(off,len,b.size()))return {};const char* p=reinterpret_cast<const char*>(b.data()+off);size_t n=0;while(n<len&&p[n])++n;return std::string(p,n);}
}
sfo_metadata read_param_sfo(const char* path) noexcept {
 sfo_metadata r; if(!path||!*path){r.description="No PARAM.SFO path supplied";return r;}
 std::ifstream f(path,std::ios::binary); if(!f){r.description="Unable to open PARAM.SFO";return r;}
 std::vector<unsigned char> b((std::istreambuf_iterator<char>(f)),{}); if(b.size()<20||le32(b.data())!=0x46535000u){r.description="Invalid PARAM.SFO header";return r;}
 uint32_t keys=le32(b.data()+8), data=le32(b.data()+12), count=le32(b.data()+16); if(count>4096||!fits(20,static_cast<uint64_t>(count)*16,b.size())){r.description="PARAM.SFO index table is invalid";return r;}
 for(uint32_t i=0;i<count;i++){const unsigned char* e=b.data()+20+i*16;uint16_t keyoff=le16(e);uint16_t format=le16(e+2);uint32_t len=le32(e+4), maxlen=le32(e+8), dataoff=le32(e+12);(void)format;(void)maxlen;
  std::string key=text_at(b,keys+keyoff,256);std::string value=text_at(b,data+dataoff,len);
  if(key=="TITLE")r.title=value;else if(key=="TITLE_ID")r.title_id=value;else if(key=="CATEGORY")r.category=value;else if(key=="APP_VER")r.app_version=value;else if(key=="VERSION")r.version=value;
 }
 r.valid=!r.title.empty()||!r.title_id.empty(); std::ostringstream s;s<<(r.valid?"PARAM.SFO metadata":"PARAM.SFO parsed without title metadata");if(!r.title_id.empty())s<<" "<<r.title_id;if(!r.title.empty())s<<" - "<<r.title;r.description=s.str();return r;
}
}
