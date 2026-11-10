# Custom Voices for Pocket-TTS

#

# Drop any custom voice files (.safetensors, .wav, .mp3, .ogg, .flac) into this directory

# (or subdirectories if specified in images/models/models.yaml).

#

# When .gitea/scripts/package-oci-model.sh runs, any files placed here will be

# automatically bundled into the harbor.alexlebens.dev/models/pocket-tts:latest OCI image

# under /models/voices/ and populated into /data/voices/ at container startup.

#

# Each voice file stem becomes the voice name:

# e.g. "my-voice.safetensors" or "my-voice.wav" is accessible as voice: "my-voice".
