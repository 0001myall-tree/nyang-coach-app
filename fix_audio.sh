cd assets/voice
for f in *.mp3; do
  if [[ ! "$f" == *"_reminder_"* ]]; then
    mv "$f" "temp_$f"
    ffmpeg -i "temp_$f" -filter:a "loudnorm" "$f" -y
    rm "temp_$f"
  fi
done
