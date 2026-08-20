# Simple Drive для Portainer

Готовое личное файловое хранилище на базе
[File Browser Quantum](https://github.com/gtsteffaniak/filebrowser).

Веб-интерфейс уже собран внутрь Docker-образа `gtstef/filebrowser:stable`.
Этот репозиторий намеренно небольшой: в нём находится только проверенная
конфигурация развёртывания, а не копия исходного кода File Browser.

Возможности веб-интерфейса:

- загрузка и скачивание файлов;
- создание, переименование и удаление папок;
- переименование, перемещение и удаление файлов;
- просмотр изображений, PDF, видео и текста;
- публичные ссылки на файлы и папки;
- прямые ссылки для `curl`, API и нейросетей.

## Схема

```text
Интернет
   │
   ▼
Внешний NGINX (HTTPS, disk.mariko-mail.ru)
   │
   ▼
IP Docker-сервера:2340
   │
   ▼
File Browser Quantum
```

## Подготовка Docker-сервера

Создайте каталог для пользовательских файлов:

```bash
sudo mkdir -p /opt/simple-drive/files
sudo chown -R 1000:1000 /opt/simple-drive/files
```

Пользователь `filebrowser` в стабильном образе работает с UID/GID `1000:1000`.
При каждом развёртывании одноразовый контейнер `simple-drive-permissions`
автоматически проверяет владельца каталога перед запуском File Browser.
Разрешите входящие соединения от внешнего NGINX к TCP-порту `2340`.

## Деплой через Portainer

1. Откройте **Stacks → Add stack**.
2. Укажите имя `simple-drive`.
3. Выберите **Git repository**.
4. Заполните:

   ```text
   Repository URL:        https://github.com/k1racle/diskmariko.git
   Repository reference: refs/heads/main
   Compose path:          compose.yaml
   ```

5. Добавьте Environment variables:

   ```env
   DATA_DIR=/opt/simple-drive/files
   APP_PORT=2340
   BIND_ADDRESS=0.0.0.0
   FILEBROWSER_IMAGE=gtstef/filebrowser:stable
   ```

6. Нажмите **Deploy the stack**.

Stack больше не монтирует `config.yaml` из Git-каталога Portainer. Это устраняет
ошибку `not a directory`, возникающую, когда Portainer и Docker daemon по-разному
видят путь `/data/compose/...`.

После запуска проверьте напрямую:

```text
http://IP_DOCKER_СЕРВЕРА:2340
```

Первый вход:

```text
Логин:  admin
Пароль: admin
```

Сразу замените пароль на уникальный.

## Настройка внешнего NGINX

NGINX должен проксировать `disk.mariko-mail.ru` на Docker-сервер:

```nginx
server {
    listen 80;
    server_name disk.mariko-mail.ru;

    location / {
        proxy_pass http://IP_DOCKER_СЕРВЕРА:2340;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        client_max_body_size 0;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

HTTPS-сертификат устанавливается на внешнем NGINX. Если сертификат уже выпускает
Certbot или панель управления NGINX, используйте их обычный способ и оставьте
upstream как `http://IP_DOCKER_СЕРВЕРА:2340`.

Не добавляйте перед File Browser дополнительный Basic Auth или OAuth: они
перекроют доступ к публичным ссылкам.

## Ссылка для нейросети

1. Войдите в File Browser.
2. Выберите файл и нажмите **Share**.
3. Создайте ссылку без пароля.
4. Скопируйте именно **Direct download link**.
5. Проверьте её извне:

   ```bash
   curl -I -L "https://disk.mariko-mail.ru/ПРЯМАЯ_ССЫЛКА"
   ```

Ответ должен быть HTTP `200`, без перехода на страницу входа.

## Хранение и резервные копии

```text
/opt/simple-drive/files         — пользовательские файлы
simple-drive_filebrowser_state  — Docker volume с аккаунтом, базой и ссылками
```

Для полного резервного копирования сохраняйте каталог с файлами и Docker volume
`simple-drive_filebrowser_state`. Перед копированием остановите Stack.

## Диагностика

Логи: **Portainer → Containers → simple-drive → Logs**.

Частые проблемы:

- `permission denied` — выполните `chown -R 1000:1000 /opt/simple-drive/files`;
- `simple-drive-permissions` завершился с ошибкой — файловая система запрещает
  `chown` (часто это NFS/SMB); права нужно настроить на стороне файлового сервера;
- порт `2340` недоступен — проверьте firewall и маршрут между NGINX и Docker;
- домен открывает не тот сайт — проверьте `server_name` и DNS;
- большая загрузка обрывается — проверьте `client_max_body_size 0` и таймауты;
- нейросеть получает страницу входа — передана Share page вместо Direct link.
