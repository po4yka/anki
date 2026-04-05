// Card display bridge for WKWebView

function showQuestion(html) {
    var qa = document.getElementById('qa');
    if (qa) {
        qa.innerHTML = html;
    }
}

function showAnswer(html) {
    var qa = document.getElementById('qa');
    if (qa) {
        qa.innerHTML = html;
    }
}
