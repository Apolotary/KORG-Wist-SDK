//
//  Synthesizer.cpp
//  WISTSample
//
//  Created by Nobuhisa Okamura on 11/05/19.
//  Copyright 2011 KORG INC. All rights reserved.
//

#include <algorithm>
#include "Synthesizer.h"
#include "Sequencer.h"
#include "DrumOscillator.h"

//  ---------------------------------------------------------------------------
//      Synthesizer::Synthesizer
//  ---------------------------------------------------------------------------
Synthesizer::Synthesizer(float samplingRate) :
samlingRate_(samplingRate),
seq_(new Sequencer(samlingRate_)),
seqEvents_(),
oscillators_()
{
    seqEvents_.reserve(100);

    const int   kNumberOfOscillator  = 4;
    const CFStringRef wavFile[kNumberOfOscillator] = { CFSTR("kick.wav"), CFSTR("snare.wav"), CFSTR("zap.wav"), CFSTR("noiz.wav") };
    for (int oscNo = 0; oscNo < kNumberOfOscillator; ++oscNo)
    {
        DrumOscillator* osc = new DrumOscillator(samlingRate_);
        osc->LoadAudioFileInResourceFolder(wavFile[oscNo]);
        osc->SetPanpot(64);
        oscillators_.push_back(osc);
    }

    seq_->SetListener(this);
}

//  ---------------------------------------------------------------------------
//      Synthesizer::~Synthesizer
//  ---------------------------------------------------------------------------
Synthesizer::~Synthesizer(void)
{
    for (size_t oscNo = 0; oscNo < oscillators_.size(); ++oscNo)
    {
        delete oscillators_[oscNo];
    }
    oscillators_.clear();

    delete seq_;
    seq_ = NULL;
}

#pragma mark -
//
//  seq event type
//
enum
{
    kSeqEventParamType_Trigger = 0,
};

//  ---------------------------------------------------------------------------
//      Synthesizer::NoteOnViaSequencer
//  ---------------------------------------------------------------------------
void
Synthesizer::NoteOnViaSequencer(int frame, int partNo)
{
    const SequencerEvent    param = { frame, kSeqEventParamType_Trigger, partNo };
    seqEvents_.push_back(param);
}

//  ---------------------------------------------------------------------------
//      Synthesizer::DecodeSeqEvent
//  ---------------------------------------------------------------------------
inline void
Synthesizer::DecodeSeqEvent(const SequencerEvent* event)
{
    switch (event->paramType)
    {
        case kSeqEventParamType_Trigger:
            {
                const int   oscNo = event->value0;
                if ((oscNo >= 0) && (oscNo < static_cast<int>(oscillators_.size())))
                {
                    oscillators_[oscNo]->TriggerOn();
                }
            }
            break;
        default:
            break;
    }
}

//  ---------------------------------------------------------------------------
//      Synthesizer::RenderAudio
//  ---------------------------------------------------------------------------
inline void
Synthesizer::RenderAudio(AudioIO* io, int16_t** buffer, int length)
{
    for (std::vector<DrumOscillator*>::iterator ite = oscillators_.begin(); ite != oscillators_.end(); ++ite)
    {
        (*ite)->Process(buffer, length);
    } 
}

//  ---------------------------------------------------------------------------
//      Synthesizer::ProcessReplacing
//  ---------------------------------------------------------------------------
void
Synthesizer::ProcessReplacing(AudioIO* io, int16_t** buffer, int length)
{
    //  clear buffer
    ::memset(buffer[0], 0, length * sizeof(int16_t));
    ::memset(buffer[1], 0, length * sizeof(int16_t));

    int rest = length;
    int offset = 0;
    while (rest > 0)
    {            
        const int   frames = rest;
        const size_t    numOfEvents = seqEvents_.size();
        const int   processed = (seq_ != NULL) ? seq_->Process(io, offset, frames) : frames;
        if (seqEvents_.size() > numOfEvents)
        {
            std::sort(seqEvents_.begin(), seqEvents_.end(), Synthesizer::SortEventFunctor);
        }
        if (processed > 0)
        {
            int procLen = processed;
            int curPos = offset;
            std::vector<SequencerEvent>::iterator ite = seqEvents_.begin();
            while (procLen > 0)
            {
                int renderLen = procLen;
                bool    decode = false;
                const bool  iteIsValid = (ite != seqEvents_.end());
                if (iteIsValid)
                {
                    const int   pos = ite->frame - curPos;
                    if (pos < procLen)
                    {
                        renderLen = pos;
                        decode = true;
                    }
                }
                if (renderLen > 0)
                {
                    int16_t*    output[] = { buffer[0] + curPos , buffer[1] + curPos };
                    this->RenderAudio(io, output, renderLen);
                }
                if (iteIsValid)
                {
                    if (decode)
                    {
                        this->DecodeSeqEvent(&(*ite));
                    }
                    ++ite;
                }
                curPos += renderLen;
                procLen -= renderLen;
            }
            seqEvents_.clear();
        }

        offset += processed;
        rest -= processed;
    }
}

#pragma mark -
//  ---------------------------------------------------------------------------
//      Synthesizer::StartSequence
//  ---------------------------------------------------------------------------
void
Synthesizer::StartSequence(uint64_t hostTime, float tempo)
{
    if (seq_ != NULL)
    {
        seq_->Start(hostTime, tempo);
    }
}

//  ---------------------------------------------------------------------------
//      Synthesizer::StopSequence
//  ---------------------------------------------------------------------------
void
Synthesizer::StopSequence(uint64_t hostTime)
{
    if (seq_ != NULL)
    {
        seq_->Stop(hostTime);
    }
}
