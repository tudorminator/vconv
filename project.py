#PY  <- Needed to identify #
#--automatically built--

adm = Avidemux() # pyright: ignore[reportUndefinedVariable]
adm.clearSegments()
adm.addSegment(0, 114558, 33935442)
adm.markerA = 0
adm.markerB = 33935442
adm.setHDRConfig(1, 1, 1, 1, 0)
adm.videoCodec("ffNvEncH264", "preset=5", "profile=1", "rc_mode=5", "quality=20", "bitrate=2500", "max_bitrate=3500", "gopsize=100", "refs=0", "bframes=0", "b_ref_mode=0", "lookahead=0", "aq_strength=1", "spatial_aq=False", "temporal_aq=False"
, "weighted_pred=False")
adm.addVideoFilter("swscale", "width=960", "height=540", "algo=2", "sourceAR=0", "targetAR=0", "lockAR=True", "roundup=0")
adm.addVideoFilter("msharpen", "mask=False", "highq=True", "chroma=False", "threshold=15", "strength=100")
adm.audioClearTracks()
adm.setSourceTrackLanguage(0,"und")
if adm.audioTotalTracksCount() <= 0:
    raise("Cannot add audio track 0, total tracks: " + str(adm.audioTotalTracksCount()))
adm.audioAddTrack(0)
adm.audioCodec(0, "LavAAC", "bitrate=128")
adm.audioSetMixer(0, "MONO");
adm.audioSetDrc2(0, 0, 1, 0.001, 0.2, 1, 2, -12)
adm.audioSetEq(0, 0, 0, 0, 0, 880, 5000)
adm.audioSetChannelGains(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
adm.audioSetChannelDelays(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
adm.audioSetChannelRemap(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)
adm.audioSetShift(0, 0, 0)
adm.setContainer("MP4", "muxerType=0", "optimize=1", "forceAspectRatio=False", "aspectRatio=1", "displayWidth=1280", "rotation=2", "clockfreq=0")
