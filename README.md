# Simple Drive для Portainer

Простой личный файловый диск на базе File Browser Quantum с отдельными публичными ссылками для людей и ИИ.

В интерфейсе доступны загрузка, скачивание, создание папок, удаление, перемещение и переименование файлов. Для каждого публичного ресурса отображаются две кнопки:

- значок буфера — копирует обычную ссылку, открывающую веб-интерфейс;
- значок робота — копирует ссылку для ИИ, возвращающую машиночитаемый JSON со списком файлов.

Кнопка для ИИ отключена у ссылок с паролем, запретом анонимного доступа и ссылок только для загрузки: внешняя нейросеть не сможет открыть их без авторизации.

## Подготовка сервера

Файлы пользователей хранятся вне контейнера:

```bash
sudo mkdir -p /opt/simple-drive/files
sudo chown -R 1000:1000 /opt/simple-drive/files
```

При каждом запуске вспомогательный контейнер также исправляет владельца каталога. Данные аккаунта, настройки и созданные публичные ссылки сохраняются в Docker volume `simple-drive_filebrowser_state`.

## Деплой через Portainer из GitHub

1. Откройте **Stacks → Add stack → Git repository**.
2. Укажите:

   ```text
   Repository URL:        https://github.com/k1racle/diskmariko.git
   Repository reference: refs/heads/main
   Compose path:          compose.yaml
   ```

3. Добавьте переменные окружения:

   ```env
   DATA_DIR=/opt/simple-drive/files
   APP_PORT=2340
   BIND_ADDRESS=0.0.0.0
   FILEBROWSER_IMAGE=simple-drive-filebrowser:1.5.2-mariko
   FILEBROWSER_VERSION=v1.5.2-stable
   ```

4. Нажмите **Deploy the stack**. При первом запуске Portainer соберёт собственный Docker-образ из закреплённой версии File Browser; это займёт несколько минут.
5. После запуска проверьте `http://IP_СЕРВЕРА:2340`.

Первый вход: логин `admin`, пароль `admin`. Сразу смените пароль.

При обновлении Git Stack не удаляйте volume, иначе будут потеряны настройки и публичные ссылки. Пользовательские файлы в `DATA_DIR` от volume не зависят.

## Nginx Proxy Manager

Proxy Host для `disk.mariko-mail.ru` должен вести на:

```text
Scheme:          http
Forward Host/IP: IP Docker-сервера
Forward Port:    2340
```

Включите SSL и Websockets Support. В **Custom Nginx Configuration** достаточно:

```nginx
client_max_body_size 0;
proxy_request_buffering off;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
```

Не добавляйте `rewrite` или отдельный `location` для `/public/share/`: этот адрес должен открывать обычный интерфейс. JSON-ссылку новая кнопка формирует отдельно через `/public/api/resources`.

## Как пользоваться двумя ссылками

1. Войдите в диск, выберите файл или папку и нажмите **Share**.
2. Создайте публичную ссылку без пароля и с разрешённым анонимным доступом.
3. В таблице ссылок нажмите:
   - кнопку с буфером — для человека;
   - кнопку с роботом — для ChatGPT или другого ИИ.

Пример обычной ссылки:

```text
https://disk.mariko-mail.ru/public/share/TW9x6EJQEW8XluYfswsRcw
```

Пример ссылки для ИИ:

```text
https://disk.mariko-mail.ru/public/api/resources?hash=TW9x6EJQEW8XluYfswsRcw&path=%2F
```

ИИ-ссылка возвращает содержимое открытой папки в JSON. Для вложенной папки клиент может повторить запрос с её путём в параметре `path`. Доступны только объекты внутри расшаренного ресурса.

## Диагностика

Логи: **Portainer → Containers → simple-drive → Logs**.

- `permission denied` — проверьте владельца `DATA_DIR`: нужен UID/GID `1000:1000`;
- сборка не скачивает исходники — Docker/BuildKit сервера должен иметь исходящий доступ к GitHub, npm и Go modules;
- обычная ссылка показывает JSON — удалите старое правило Nginx для `/public/share/`;
- кнопка с роботом неактивна — ссылка защищена паролем, запрещает анонимный доступ или предназначена только для загрузки;
- большие загрузки обрываются — проверьте `client_max_body_size`, `proxy_read_timeout` и `proxy_send_timeout` в Nginx Proxy Manager.
