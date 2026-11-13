<%@ Page Language="C#" %>
<%--
    Steel Ball Run - Rider Registration
    INTENTIONALLY VULNERABLE (lab use only):
      - Extension is only checked client-side (JavaScript).
      - Server trusts the client-supplied Content-Type header.
      - Original filename is kept and saved inside the web root (/uploads/),
        where IIS will happily execute .aspx files.
--%>
<script runat="server">
    protected string Message = "";
    protected string MessageClass = "notice";

    protected void Page_Load(object sender, EventArgs e)
    {
        if (Request.HttpMethod != "POST") return;

        string rider = (Request.Form["riderName"] ?? "").Trim();
        string horse = (Request.Form["horseName"] ?? "").Trim();
        HttpPostedFile photo = Request.Files["horsePhoto"];

        if (rider.Length == 0 || horse.Length == 0)
        {
            Message = "Rider and horse names are required.";
            return;
        }
        if (photo == null || photo.ContentLength == 0)
        {
            Message = "Please attach a photo of your horse.";
            return;
        }

        string[] allowedTypes = { "image/jpeg", "image/png", "image/gif" };
        if (Array.IndexOf(allowedTypes, (photo.ContentType ?? "").ToLowerInvariant()) < 0)
        {
            Message = "Rejected: only JPEG, PNG or GIF images are accepted (received " +
                      Server.HtmlEncode(photo.ContentType) + ").";
            return;
        }

        string fileName = System.IO.Path.GetFileName(photo.FileName);
        photo.SaveAs(Server.MapPath("~/uploads/" + fileName));

        Message = "Thank you, " + Server.HtmlEncode(rider) + "! " + Server.HtmlEncode(horse) +
                  " has been registered. Your photo is on file at <a href=\"uploads/" +
                  Server.UrlPathEncode(fileName) + "\">/uploads/" + Server.HtmlEncode(fileName) + "</a>.";
        MessageClass = "card";
    }
</script>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Steel Ball Run - Rider Registration</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
<header>
    <h1>Rider Registration</h1>
    <p>Steel Ball Run &mdash; San Diego Beach, September 25th, 1890</p>
</header>
<nav>
    <a href="index.html">Home</a>
    <a href="register.aspx">Rider Registration</a>
    <a href="index.html#officials">Race Officials</a>
</nav>
<main>
    <% if (Message.Length > 0) { %>
        <div class="<%= MessageClass %>"><%= Message %></div>
    <% } %>

    <div class="card">
        <p>
            Every rider must submit a photograph of their horse. Officials at each checkpoint
            will compare the horse against your registration photo. Accepted formats:
            <strong>.jpg, .png, .gif</strong>.
        </p>
        <form method="post" action="register.aspx" enctype="multipart/form-data" onsubmit="return checkPhoto();">
            <label for="riderName">Rider name</label>
            <input type="text" id="riderName" name="riderName" placeholder="Gyro Zeppeli">

            <label for="horseName">Horse name</label>
            <input type="text" id="horseName" name="horseName" placeholder="Valkyrie">

            <label for="horsePhoto">Horse photo</label>
            <input type="file" id="horsePhoto" name="horsePhoto" accept=".jpg,.jpeg,.png,.gif">

            <button type="submit">Register</button>
        </form>
    </div>
</main>
<footer>
    &copy; 1890 Steel Ball Run Race Office
</footer>
<script>
    function checkPhoto() {
        var f = document.getElementById('horsePhoto').value.toLowerCase();
        if (!/\.(jpe?g|png|gif)$/.test(f)) {
            alert('Only image files (.jpg, .png, .gif) may be uploaded.');
            return false;
        }
        return true;
    }
</script>
</body>
</html>
