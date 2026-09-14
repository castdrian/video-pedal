#import <Foundation/Foundation.h>

typedef void *VPOBSOutputRef;

#ifdef __cplusplus
extern "C" {
#endif

VPOBSOutputRef VPOBSOutputCreate(int width, int height);
BOOL VPOBSOutputSendBGRA(VPOBSOutputRef output, const unsigned char *pixels, size_t bytesPerRow, uint64_t hostTimeNs);
void VPOBSOutputDestroy(VPOBSOutputRef output);

#ifdef __cplusplus
}
#endif
