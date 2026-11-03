#pragma once
#include "image.h"
#include <sys/stat.h>
namespace gremote::gpu {
struct SourceIdentity {
  dev_t device=0;ino_t inode=0;off_t size=0;int64_t modified=0,changed=0;
  bool operator==(const SourceIdentity& b)const{return device==b.device&&inode==b.inode&&size==b.size&&modified==b.modified&&changed==b.changed;}
};
SourceIdentity IdentifySource(int fd);
// Consumes owned fd on every path; source dimensions remain raw (EXIF in shader).
Image LoadSource(int fd,int version,bool adobe_rgb,SourceIdentity* identity);
}
