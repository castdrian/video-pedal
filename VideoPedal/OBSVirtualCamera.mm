#import "OBSVirtualCamera.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreVideo/CoreVideo.h>

#include <algorithm>
#include <cstring>
#include <mutex>
#include <vector>

namespace {
constexpr const char *kOBSDeviceUID = "7626645E-4425-469E-9D8B-97E0FA59AC75";

static uint8_t clampByte(int value) { return static_cast<uint8_t>(std::max(0, std::min(255, value))); }

static void bgraToUYVY(const uint8_t *source, size_t sourceBytesPerRow, uint8_t *destination, int width, int height) {
    for (int y = 0; y < height; ++y) {
        const uint8_t *sourceRow = source + y * sourceBytesPerRow;
        uint8_t *destinationRow = destination + y * width * 2;
        for (int x = 0; x < width; x += 2) {
            const uint8_t *first = sourceRow + x * 4;
            const uint8_t *second = sourceRow + std::min(x + 1, width - 1) * 4;
            const int firstY = ((66 * first[2] + 129 * first[1] + 25 * first[0] + 128) >> 8) + 16;
            const int secondY = ((66 * second[2] + 129 * second[1] + 25 * second[0] + 128) >> 8) + 16;
            const int firstU = ((-38 * first[2] - 74 * first[1] + 112 * first[0] + 128) >> 8) + 128;
            const int secondU = ((-38 * second[2] - 74 * second[1] + 112 * second[0] + 128) >> 8) + 128;
            const int firstV = ((112 * first[2] - 94 * first[1] - 18 * first[0] + 128) >> 8) + 128;
            const int secondV = ((112 * second[2] - 94 * second[1] - 18 * second[0] + 128) >> 8) + 128;
            destinationRow[x * 2] = clampByte((firstU + secondU) / 2);
            destinationRow[x * 2 + 1] = clampByte(firstY);
            destinationRow[x * 2 + 2] = clampByte((firstV + secondV) / 2);
            destinationRow[x * 2 + 3] = clampByte(secondY);
        }
    }
}

class OBSOutput {
public:
    OBSOutput(int width, int height) : width(width), height(height), guard(mutex, std::try_to_lock) {
        if (!guard.owns_lock()) return;
        CMIOObjectPropertyAddress address = {kCMIOHardwarePropertyDevices, kCMIOObjectPropertyScopeGlobal, kCMIOObjectPropertyElementMain};
        UInt32 size = 0;
        UInt32 used = 0;
        if (CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject, &address, 0, nullptr, &size) != noErr) return;
        std::vector<CMIOObjectID> devices(size / sizeof(CMIOObjectID));
        if (CMIOObjectGetPropertyData(kCMIOObjectSystemObject, &address, 0, nullptr, size, &used, devices.data()) != noErr) return;

        address.mSelector = kCMIODevicePropertyDeviceUID;
        for (CMIOObjectID candidate : devices) {
            CFStringRef uid = nullptr;
            if (CMIOObjectGetPropertyData(candidate, &address, 0, nullptr, sizeof(uid), &used, &uid) != noErr || !uid) continue;
            char uidBuffer[128] = {};
            bool matches = CFStringGetCString(uid, uidBuffer, sizeof(uidBuffer), kCFStringEncodingUTF8) && std::strcmp(uidBuffer, kOBSDeviceUID) == 0;
            CFRelease(uid);
            if (matches) { deviceID = candidate; break; }
        }
        if (!deviceID) return;

        address.mSelector = kCMIODevicePropertyStreams;
        if (CMIOObjectGetPropertyDataSize(deviceID, &address, 0, nullptr, &size) != noErr) return;
        std::vector<CMIOStreamID> streams(size / sizeof(CMIOStreamID));
        if (streams.size() < 2 || CMIOObjectGetPropertyData(deviceID, &address, 0, nullptr, size, &used, streams.data()) != noErr) return;
        streamID = streams[1];
        if (CMIOStreamCopyBufferQueue(streamID, [](CMIOStreamID, void *, void *) {}, nullptr, &queue) != noErr) return;
        if (CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_422YpCbCr8, width, height, nullptr, &formatDescription) != noErr) return;
        if (CMIODeviceStartStream(deviceID, streamID) != noErr) return;
        outputBuffer.resize(static_cast<size_t>(width) * height * 2);
        valid = true;
    }

    ~OBSOutput() {
        if (valid) CMIODeviceStopStream(deviceID, streamID);
        if (queue) CFRelease(queue);
        if (formatDescription) CFRelease(formatDescription);
    }

    bool send(const uint8_t *pixels, size_t bytesPerRow, uint64_t hostTimeNs) {
        if (!valid || !pixels) return false;
        bgraToUYVY(pixels, bytesPerRow, outputBuffer.data(), width, height);
        NSDictionary *poolAttributes = @{};
        NSDictionary *bufferAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_422YpCbCr8),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        CVPixelBufferPoolRef pool = nullptr;
        if (CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)poolAttributes, (__bridge CFDictionaryRef)bufferAttributes, &pool) != kCVReturnSuccess) return false;
        CVPixelBufferRef pixelBuffer = nullptr;
        CVReturn result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer);
        CVPixelBufferPoolRelease(pool);
        if (result != kCVReturnSuccess || !pixelBuffer) return false;
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        std::memcpy(CVPixelBufferGetBaseAddress(pixelBuffer), outputBuffer.data(), outputBuffer.size());
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CMSampleTimingInfo timing = {CMTimeMake(static_cast<int64_t>(hostTimeNs), 1000000000), kCMTimeInvalid, kCMTimeInvalid};
        CMSampleBufferRef sampleBuffer = nullptr;
        result = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nullptr, nullptr, formatDescription, &timing, &sampleBuffer);
        CVPixelBufferRelease(pixelBuffer);
        if (result != noErr || !sampleBuffer) return false;
        CMSimpleQueueEnqueue(queue, sampleBuffer);
        return true;
    }

    bool isValid() const { return valid; }

private:
    static std::mutex mutex;
    std::unique_lock<std::mutex> guard;
    int width;
    int height;
    CMIOObjectID deviceID = 0;
    CMIOStreamID streamID = 0;
    CMSimpleQueueRef queue = nullptr;
    CMFormatDescriptionRef formatDescription = nullptr;
    std::vector<uint8_t> outputBuffer;
    bool valid = false;
};

std::mutex OBSOutput::mutex;
}

VPOBSOutputRef VPOBSOutputCreate(int width, int height) {
    OBSOutput *output = new OBSOutput(width, height);
    if (!output->isValid()) { delete output; return nullptr; }
    return output;
}

BOOL VPOBSOutputSendBGRA(VPOBSOutputRef output, const unsigned char *pixels, size_t bytesPerRow, uint64_t hostTimeNs) {
    return output && static_cast<OBSOutput *>(output)->send(pixels, bytesPerRow, hostTimeNs);
}

void VPOBSOutputDestroy(VPOBSOutputRef output) { delete static_cast<OBSOutput *>(output); }