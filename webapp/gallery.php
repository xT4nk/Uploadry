<?php
// Public gallery: lists whatever is in /uploads (no auth).
$dir = __DIR__ . '/uploads';
$files = array_values(array_filter(scandir($dir), function ($f) {
    return !in_array($f, ['.', '..', '.keep']);
}));
?>
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Gallery</title>
<style>body{font-family:system-ui,Arial;max-width:720px;margin:3rem auto;padding:0 1rem}
img{max-width:180px;margin:6px;border:1px solid #ddd;border-radius:6px}</style></head>
<body>
  <h1>Gallery</h1>
  <p><a href="/">&larr; home</a></p>
  <?php if (!$files): ?>
    <p><em>No photos yet. Upload some from the admin panel.</em></p>
  <?php else: foreach ($files as $f): ?>
    <a href="/uploads/<?= htmlspecialchars($f) ?>"><img src="/uploads/<?= htmlspecialchars($f) ?>" alt=""></a>
  <?php endforeach; endif; ?>
</body>
</html>
