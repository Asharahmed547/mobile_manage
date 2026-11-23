# Stage 1: Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN flutter pub get
COPY . .

ARG GEMINI_API_KEY
ARG GROK_API_KEY

RUN flutter build web --release \
    --dart-define=GEMINI_API_KEY=$GEMINI_API_KEY \
    --dart-define=GROK_API_KEY=$GROK_API_KEY

# Stage 2: Nginx Alpine Server
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]