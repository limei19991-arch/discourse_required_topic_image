# Discourse Topic Cover

Adds an explicit cover-image field to the native Discourse topic composer.

## Features

- Keeps the native title, category and tag controls.
- Adds an image uploader directly below those controls.
- Renders the cover in a dedicated row above the post stream, independently from cooked post content.
- Stores the upload ID in the `topic_cover_upload_id` topic custom field.
- Creates a bounded WebP variant and stores its URL in `topic_cover_upload_url` for query-free rendering.
- Validates required covers and image ownership on the server.
- Creates a durable `UploadReference` attached to the cover custom-field record.
- Returns `topic_cover_upload_id`, `topic_cover_url`, and Topic List Thumbnails-compatible data.
- Supports replacing the cover while editing the first post.
- Shows an indeterminate publishing progress bar while the cover is processed.

## Topic-list data

Each serialized topic-list item contains:

```json
{
  "topic_cover_upload_id": 123,
  "topic_cover_url": "/uploads/default/optimized/1X/example.webp"
}
```

Themes and theme components should render `topic.topic_cover_url` directly instead of scanning the first post for an image.

## Installation

Add the repository to the `hooks.after_code` plugin list in `containers/app.yml`, then rebuild the Discourse container.

## Settings

- `topic cover enabled`
- `topic cover required`
- `topic cover min width` / `topic cover min height`
- `topic cover max width` / `topic cover max height`
- `topic cover image quality`
