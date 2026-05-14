#!/bin/bash

# Create the config directory
mkdir -p lib/config

# Create the secrets.dart file safely using Vercel environment variables
printf "class Secrets { static const String supabaseUrl = '%s'; static const String supabaseKey = '%s'; }\n" "$SUPABASE_URL" "$SUPABASE_KEY" > lib/config/secrets.dart

# Download Flutter if it doesn't exist on the Vercel server
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi

# Build the web app
./flutter/bin/flutter build web --release
