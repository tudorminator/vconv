#PY  <- Needed to identify #
#--automatically built--
adm = Avidemux() # pyright: ignore[reportUndefinedVariable]
if not adm.loadVideo("${INPUT_FILE}"):
    raise("Cannot load video: ${INPUT_FILE}")
adm.setHDRConfig(1, 1, 1, 1, 0)
adm.videoCodec("ffNvEncHEVC", "preset=5", "profile=0", "rc_mode=0", "quality=20", "bitrate=2000", "max_bitrate=10000", "gopsize=100", "refs=0", "bframes=0", "b_ref_mode=2", "lookahead=0", "aq_strength=1", "spatial_aq=False", "temporal_aq=False"
, "weighted_pred=False")
adm.addVideoFilter("swscale", "width=${SCALE_WIDTH}", "height=${SCALE_HEIGHT}", "algo=2", "sourceAR=0", "targetAR=0", "lockAR=True", "roundup=0")
adm.addVideoFilter("msharpen", "mask=False", "highq=True", "chroma=False", "threshold=15", "strength=100")
adm.audioClearTracks()
if adm.audioTotalTracksCount() > 0:
    adm.setSourceTrackLanguage(0, "und")
    adm.audioAddTrack(0)
    adm.audioCodec(0, "LavAAC", "bitrate=128")
    adm.audioSetMixer(0, "MONO")
    adm.audioSetDrc2(0, 0, 1, 0.001, 0.2, 1, 2, -12)
    adm.audioSetEq(0, 0, 0, 0, 0, 880, 5000)
    adm.audioSetChannelGains(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    adm.audioSetChannelDelays(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    adm.audioSetChannelRemap(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)
    adm.audioSetShift(0, 0, 0)
adm.setContainer("MP4", "muxerType=0", "optimize=1", "forceAspectRatio=False", "aspectRatio=1", "displayWidth=${SCALE_WIDTH}", "rotation=${ROTATION}", "clockfreq=0")
if not adm.save("${OUTPUT_FILE}"):
    raise("Cannot save video to: ${OUTPUT_FILE}")
