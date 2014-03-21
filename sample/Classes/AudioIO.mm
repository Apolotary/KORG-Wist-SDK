//
//  AudioIO.mm
//  WISTSample
//
//  Created by Nobuhisa Okamura on 11/05/19.
//  Copyright 2011 KORG INC. All rights reserved.
//

#include <mach/mach_time.h>
#include "AudioIO.h"

#define ThrowIfOSStatus_(err)           \
    do {                                \
        OSStatus __theErr = err;        \
        if (__theErr != noErr) {        \
            throw(OSStatus)(__theErr);  \
        }                               \
    } while (false)

//  ---------------------------------------------------------------------------
//      AudioIO::AudioIO
//  ---------------------------------------------------------------------------
AudioIO::AudioIO(float samplingRate) :
listener_(NULL),
bufferLength_(4096),
numberOfOutputBus_(2),
sampleRate_(samplingRate),
ioBufferSize_(1024),   //  audio I/O buffer size
remoteIOUnit_(NULL),
auGraph_(NULL),
isRunning_(false),
dataBuffer_(),
outputBuffer_(),
hostTime_(0),
latency_(0)
{
    dataBuffer_.assign(bufferLength_ * numberOfOutputBus_, 0);
    outputBuffer_.clear();
    for (uint32_t ch = 0; ch < numberOfOutputBus_; ++ch)
    {
        outputBuffer_.push_back(&dataBuffer_[bufferLength_ * ch]);
    }

    this->InitializeAudioSession();
}

//  ---------------------------------------------------------------------------
//      AudioIO::~AudioIO
//  ---------------------------------------------------------------------------
AudioIO::~AudioIO(void)
{
    this->Stop();
    this->Close();
}

//  ---------------------------------------------------------------------------
//      AudioIO::InitializeAudioSession
//  ---------------------------------------------------------------------------
void
AudioIO::InitializeAudioSession(void)
{
    try
    {
        ThrowIfOSStatus_(::AudioSessionInitialize(NULL, NULL, AudioIO::InterruptionCallback, this));
        ThrowIfOSStatus_(::AudioSessionSetActive(true));
        const UInt32    audioCategory = kAudioSessionCategory_MediaPlayback;
        ThrowIfOSStatus_(::AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(audioCategory), &audioCategory));
        const UInt32    mixOthers = 1;
        ThrowIfOSStatus_(::AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(mixOthers), &mixOthers));
        ThrowIfOSStatus_(::AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, AudioRouteChangeCallback, this));
        this->SetIOBufferSize();
    }
    catch(OSStatus& inErr)
    {
        DEBUG_LOG(@"AudioIO::InitializeAudioSession() failed : result = %d", (int)inErr);
    }
}

//  ---------------------------------------------------------------------------
//      SetDesc
//  ---------------------------------------------------------------------------
static inline void
SetDesc(AudioStreamBasicDescription& desc, float fs, UInt32 numOfChannels)
{
    desc.mSampleRate = fs;
    desc.mFormatID = kAudioFormatLinearPCM;
    desc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    desc.mBitsPerChannel = sizeof(AudioSampleType) * 8;
    desc.mFramesPerPacket = 1; 
    desc.mChannelsPerFrame = numOfChannels;
    desc.mBytesPerFrame = desc.mBitsPerChannel / 8 * desc.mChannelsPerFrame;
    desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
    desc.mReserved = 0;
}

//  ---------------------------------------------------------------------------
//      AudioIO::Open
//  ---------------------------------------------------------------------------
bool
AudioIO::Open(void)
{
    bool    result = true;
    try
    {
        ThrowIfOSStatus_(::NewAUGraph(&auGraph_));
        ThrowIfOSStatus_(::AUGraphOpen(auGraph_));

        AudioComponentDescription   cd;
        cd.componentType = kAudioUnitType_Output;
        cd.componentSubType = kAudioUnitSubType_RemoteIO;
        cd.componentManufacturer = kAudioUnitManufacturer_Apple;
        cd.componentFlags = 0;
        cd.componentFlagsMask = 0;

        AUNode  remoteIONode;
        ThrowIfOSStatus_(::AUGraphAddNode(auGraph_, &cd, &remoteIONode));
        ThrowIfOSStatus_(::AUGraphNodeInfo(auGraph_, remoteIONode, NULL, &remoteIOUnit_));
        
        const UInt32    enableAudioInput = 0;   //  input disabled
        ThrowIfOSStatus_(::AudioUnitSetProperty(remoteIOUnit_, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input,
                                                1, &enableAudioInput, sizeof(enableAudioInput)));

        AudioStreamBasicDescription audioFormat;
        SetDesc(audioFormat, sampleRate_, numberOfOutputBus_);
        ThrowIfOSStatus_(::AudioUnitSetProperty(remoteIOUnit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
                                                1, &audioFormat, sizeof(audioFormat)));
        ThrowIfOSStatus_(::AudioUnitSetProperty(remoteIOUnit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                                0, &audioFormat, sizeof(audioFormat)));

        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = AudioIO::RenderCallback;
        callbackStruct.inputProcRefCon = this;
        ThrowIfOSStatus_(::AUGraphSetNodeInputCallback(auGraph_, remoteIONode, 0, &callbackStruct));

        ThrowIfOSStatus_(::AUGraphInitialize(auGraph_));
    }
    catch(OSStatus& inErr)
    {
        DEBUG_LOG(@"AudioIO::Open() failed : result = %d", (int)inErr);
        result = false;
    }
    return result;
}

//  ---------------------------------------------------------------------------
//      AudioIO::Close
//  ---------------------------------------------------------------------------
bool
AudioIO::Close(void)
{
    bool    ret = false;
    if (auGraph_ != NULL)
    {
        const OSStatus  err = ::AUGraphUninitialize(auGraph_);
        ret = (err == noErr);
        auGraph_ = NULL;
    }
    return ret;
}

//  ---------------------------------------------------------------------------
//      AudioIO::Start
//  ---------------------------------------------------------------------------
bool
AudioIO::Start(void)
{
    bool    ret = false;
    if (auGraph_ != NULL)
    {
        const OSStatus  err = ::AUGraphStart(auGraph_);
        ret = (err == noErr);
        isRunning_ = true;
    }
    return ret;
}

//  ---------------------------------------------------------------------------
//      AudioIO::Stop
//  ---------------------------------------------------------------------------
bool
AudioIO::Stop(void)
{
    bool    ret = false;
    if (auGraph_ != NULL)
    {
        const OSStatus  err = ::AUGraphStop(auGraph_);
        ret = (err == noErr);
        isRunning_ = false;
    }
    return ret;
}

//  ---------------------------------------------------------------------------
//      AudioIO::IsRunning
//  ---------------------------------------------------------------------------
bool
AudioIO::IsRunning(void) const
{
    return isRunning_;
}

//  ---------------------------------------------------------------------------
//      AudioIO::SetIOBufferSize
//  ---------------------------------------------------------------------------
void
AudioIO::SetIOBufferSize(void)
{
    try
    {
        Float32 duration = static_cast<float>(ioBufferSize_) / sampleRate_;
        ThrowIfOSStatus_(::AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration, sizeof(duration), &duration));
        UInt32  size = sizeof(duration);
        ThrowIfOSStatus_(::AudioSessionGetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration, &size, &duration));
        latency_ = static_cast<UInt64>(duration * 1000000000ULL);
    }
    catch(OSStatus& inErr)
    {
        DEBUG_LOG(@"AudioIO::SetIOBufferSize() failed : result = %d", (int)inErr);
    }
}

#pragma mark - render callback
//  ---------------------------------------------------------------------------
//      ConvertSInt16ToAudioSampleType
//  ---------------------------------------------------------------------------
static inline AudioSampleType
ConvertSInt16ToAudioSampleType(int16_t sample)
{
    return sample;
}

//  ---------------------------------------------------------------------------
//      AudioIO::Render
//  ---------------------------------------------------------------------------
void
AudioIO::Render(AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
                AudioBufferList* ioData)
{
    if ((inTimeStamp != NULL) && ((inTimeStamp->mFlags & kAudioTimeStampHostTimeValid) != 0))
    {
        hostTime_ = inTimeStamp->mHostTime;
    }
    else
    {
        hostTime_ = 0;
    }

    //  render
    if (listener_ != NULL)
    {
        AudioSampleType*    dataBufPtr = reinterpret_cast<AudioSampleType*>(ioData->mBuffers[0].mData);
        uint32_t    rest = inNumberFrames;
        while (rest > 0)
        {
            const uint32_t  processLength = (rest < bufferLength_) ? rest : bufferLength_;
            listener_->ProcessReplacing(this, &outputBuffer_[0], processLength);
            for (uint32_t bus = 0; bus < numberOfOutputBus_; ++bus)
            {
                const int16_t*  srcPtr = outputBuffer_[bus];
                AudioSampleType*    destPtr = dataBufPtr + bus;
                for (uint32_t i = 0; i < processLength; ++i, destPtr += numberOfOutputBus_, ++srcPtr)
                {
                    *destPtr = ConvertSInt16ToAudioSampleType(*srcPtr);
                }
            }
            rest -= processLength;
            dataBufPtr += processLength * numberOfOutputBus_;

            if (rest > 0)
            {
                mach_timebase_info_data_t   timeInfo;
                mach_timebase_info(&timeInfo);
                const uint64_t  timeNano = static_cast<uint64_t>(static_cast<float>(processLength) * 1000000000ULL / sampleRate_);
                hostTime_ += timeNano * timeInfo.denom / timeInfo.numer;
            }
        }
    }
}

//  ---------------------------------------------------------------------------
//      AudioIO::RenderCallback                                     [static]
//  ---------------------------------------------------------------------------
OSStatus
AudioIO::RenderCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp,
                        UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList* ioData)
{
    NSAutoreleasePool*  pool = [[NSAutoreleasePool alloc] init];
    AudioIO*  io = reinterpret_cast<AudioIO*>(inRefCon);
    io->Render(ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);
    [pool release];
    return noErr;
}

//  ---------------------------------------------------------------------------
//      AudioIO::SetListener
//  ---------------------------------------------------------------------------
void
AudioIO::SetListener(AudioIOListener* listener)
{
    listener_ = listener;
}

#pragma mark - notification callback
//  ---------------------------------------------------------------------------
//      AudioIO::Interrupt
//  ---------------------------------------------------------------------------
void
AudioIO::Interrupt(UInt32 state)
{
    switch (state)
    {
        case kAudioSessionBeginInterruption:
            this->Stop();
            break;
        case kAudioSessionEndInterruption:
            ::AudioSessionSetActive(true);
            this->Start();
            break;
        default:
            break;
    }
}

//  ---------------------------------------------------------------------------
//      AudioIO::InterruptionCallback                               [static]
//  ---------------------------------------------------------------------------
void
AudioIO::InterruptionCallback(void* inClientData, UInt32 inInterruptionState)
{
    AudioIO*  io = reinterpret_cast<AudioIO*>(inClientData);
    io->Interrupt(inInterruptionState);
}

//  ---------------------------------------------------------------------------
//      AudioIO::AudioRouteChange
//  ---------------------------------------------------------------------------
void
AudioIO::AudioRouteChange(AudioSessionPropertyID inID, UInt32 inDataSize, const void* inData)
{
    switch (inID)
    {
        case kAudioSessionProperty_AudioRouteChange:
            this->SetIOBufferSize();
            break;
        default:
            break;
    }
}

//  ---------------------------------------------------------------------------
//      AudioIO::AudioRouteChangeCallback                           [static]
//  ---------------------------------------------------------------------------
void
AudioIO::AudioRouteChangeCallback(void* inClientData, AudioSessionPropertyID inID, UInt32 inDataSize, const void* inData)
{
    AudioIO*    io = reinterpret_cast<AudioIO*>(inClientData);
    io->AudioRouteChange(inID, inDataSize, inData);
}

#pragma mark -
//  ---------------------------------------------------------------------------
//      AudioIO::GetCPULoad
//  ---------------------------------------------------------------------------
Float32
AudioIO::GetCPULoad(void) const
{
    Float32 result = 0.0f;
    if (auGraph_ != NULL)
    {
        Float32 load = 0.0f;
        if (::AUGraphGetCPULoad(auGraph_, &load) == noErr)
        {
            result = load;
        }
    }
    return result;
}

//  ---------------------------------------------------------------------------
//      AudioIO::GetMaxCPULoad
//  ---------------------------------------------------------------------------
Float32
AudioIO::GetMaxCPULoad(void) const
{
    Float32 result = 0.0f;
    if (auGraph_ != NULL)
    {
        Float32 load = 0.0f;
        if (::AUGraphGetMaxCPULoad(auGraph_, &load) == noErr)
        {
            result = load;
        }
    }
    return result;
}
