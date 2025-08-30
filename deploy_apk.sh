#!/bin/bash

# Путь к собранному APK (может отличаться)
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

# Проверяем, существует ли файл
if [ ! -f "$APK_PATH" ]; then
  echo "❌ APK не найден: $APK_PATH"
  exit 1
fi

# Загружаем на сервер
echo "📤 Загружаю APK на сервер..."
scp "$APK_PATH" root@eom-sharing.duckdns.org:/root/eom/uploads/app/app-release.apk

if [ $? -eq 0 ]; then
  echo "✅ Успешно загружено: https://eom-sharing.duckdns.org/uploads/app/app-release.apk"
else
  echo "❌ Ошибка при загрузке"
  exit 1
fi