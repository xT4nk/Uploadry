<?php
session_start();
if (empty($_SESSION['auth'])) {
    header('Location: /admin/');
    exit;
}

$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['photo'])) {
    $f    = $_FILES['photo'];
    $name = basename($f['name']);
    $ext  = strtolower(pathinfo($name, PATHINFO_EXTENSION));

    // Reject by MIME type (from the client) and by a blacklist of extensions.
    $blacklist   = ['php', 'php2', 'html', 'htm', 'js'];
    $allowedMime = ['image/jpeg', 'image/png', 'image/gif'];

    if (!in_array($f['type'], $allowedMime, true)) {
        $err = 'Only image uploads are allowed (bad MIME type).';
    } elseif (in_array($ext, $blacklist, true)) {
        $err = 'That file extension is not allowed.';
    } else {
        $dest = __DIR__ . '/../uploads/' . $name;
        if (move_uploaded_file($f['tmp_name'], $dest)) {
            $msg = 'Uploaded: ' . htmlspecialchars($name);
        } else {
            $err = 'Upload failed.';
        }
    }
}
?>
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Uploader</title>
<style>body{font-family:system-ui,Arial;max-width:520px;margin:4rem auto;padding:0 1rem}
.ok{color:#15803d}.err{color:#b91c1c}</style></head>
<body>
  <h1>Photo uploader</h1>
  <p>Logged in as <strong>admin</strong> &mdash; <a href="/gallery.php">view gallery</a></p>
  <?php if ($msg): ?><p class="ok"><?= $msg ?></p><?php endif; ?>
  <?php if ($err): ?><p class="err"><?= htmlspecialchars($err) ?></p><?php endif; ?>
  <form method="post" enctype="multipart/form-data">
    <input type="file" name="photo" accept="image/*">
    <button type="submit">Upload</button>
  </form>
  <p><small>Accepted: JPG, PNG, GIF.</small></p>
</body>
</html>
