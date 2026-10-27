<?php
session_start();
require __DIR__ . '/config.php';

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = $_POST['username'] ?? '';
    $p = $_POST['password'] ?? '';
    if ($u === $ADMIN_USER && $p === $ADMIN_PASS) {
        $_SESSION['auth'] = true;
        header('Location: /admin/dashboard.php');
        exit;
    }
    $error = 'Invalid credentials.';
}
?>
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Admin login</title>
<style>body{font-family:system-ui,Arial;max-width:360px;margin:5rem auto;padding:0 1rem}
input{display:block;width:100%;padding:.5rem;margin:.4rem 0;box-sizing:border-box}
button{padding:.5rem 1rem} .err{color:#b91c1c}</style></head>
<body>
  <h1>Admin login</h1>
  <?php if ($error): ?><p class="err"><?= htmlspecialchars($error) ?></p><?php endif; ?>
  <form method="post">
    <input name="username" placeholder="username" autofocus>
    <input name="password" type="password" placeholder="password">
    <button type="submit">Sign in</button>
  </form>
</body>
</html>
