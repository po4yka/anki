// Image Occlusion rendering for CardWebView
// Reads data-attribute divs produced by {{cloze:occlusions}} and draws on canvas

window.anki = window.anki || {};

anki.imageOcclusion = {
    setup: function () {
        var container = document.getElementById('image-occlusion-container');
        if (!container) return;

        var img = container.querySelector('img');
        var canvas = document.getElementById('image-occlusion-canvas');
        if (!img || !canvas) return;

        var draw = function () {
            var w = img.clientWidth;
            var h = img.clientHeight;
            if (w === 0 || h === 0) return;

            canvas.width = w;
            canvas.height = h;
            canvas.style.width = w + 'px';
            canvas.style.height = h + 'px';

            var ctx = canvas.getContext('2d');
            ctx.clearRect(0, 0, w, h);

            var style = getComputedStyle(canvas);
            var activeColor = style.getPropertyValue('--active-shape-color').trim() || '#ff8e8e';
            var inactiveColor = style.getPropertyValue('--inactive-shape-color').trim() || '#ffeba2';
            var highlightColor = style.getPropertyValue('--highlight-shape-color').trim() || 'rgba(255,142,142,0)';
            var activeBorder = style.getPropertyValue('--active-shape-border').trim() || '1px #212121';
            var inactiveBorder = style.getPropertyValue('--inactive-shape-border').trim() || '1px #212121';
            var highlightBorder = style.getPropertyValue('--highlight-shape-border').trim() || '1px #ff8e8e';

            var divs = document.querySelectorAll('.cloze, .cloze-inactive, .cloze-highlight');
            divs.forEach(function (div) {
                var cls = div.className;
                var fill, border;
                if (cls.indexOf('cloze-highlight') !== -1) {
                    fill = highlightColor;
                    border = highlightBorder;
                } else if (cls.indexOf('cloze-inactive') !== -1) {
                    fill = inactiveColor;
                    border = inactiveBorder;
                } else {
                    fill = activeColor;
                    border = activeBorder;
                }

                var borderParts = border.split(' ');
                var borderWidth = parseFloat(borderParts[0]) || 1;
                var borderColor = borderParts[1] || '#212121';

                var shape = div.dataset.shape;
                if (!shape) return;

                var left = parseFloat(div.dataset.left) || 0;
                var top = parseFloat(div.dataset.top) || 0;
                var sw = parseFloat(div.dataset.width) || 0;
                var sh = parseFloat(div.dataset.height) || 0;
                var angle = parseFloat(div.dataset.angle) || 0;

                ctx.save();
                ctx.fillStyle = fill;
                ctx.strokeStyle = borderColor;
                ctx.lineWidth = borderWidth;

                if (shape === 'rect') {
                    var rx = left * w;
                    var ry = top * h;
                    var rw = sw * w;
                    var rh = sh * h;
                    if (angle) {
                        ctx.translate(rx + rw / 2, ry + rh / 2);
                        ctx.rotate((angle * Math.PI) / 180);
                        ctx.fillRect(-rw / 2, -rh / 2, rw, rh);
                        ctx.strokeRect(-rw / 2, -rh / 2, rw, rh);
                    } else {
                        ctx.fillRect(rx, ry, rw, rh);
                        ctx.strokeRect(rx, ry, rw, rh);
                    }
                } else if (shape === 'ellipse') {
                    var erx = (parseFloat(div.dataset.rx) || sw / 2) * w;
                    var ery = (parseFloat(div.dataset.ry) || sh / 2) * h;
                    var ecx = left * w + (sw * w) / 2;
                    var ecy = top * h + (sh * h) / 2;
                    ctx.beginPath();
                    ctx.ellipse(ecx, ecy, erx, ery, (angle * Math.PI) / 180, 0, 2 * Math.PI);
                    ctx.fill();
                    ctx.stroke();
                } else if (shape === 'polygon') {
                    var points = (div.dataset.points || '').split(' ');
                    if (points.length >= 3) {
                        ctx.beginPath();
                        points.forEach(function (pt, i) {
                            var coords = pt.split(',');
                            var px = parseFloat(coords[0]) * w;
                            var py = parseFloat(coords[1]) * h;
                            if (i === 0) ctx.moveTo(px, py);
                            else ctx.lineTo(px, py);
                        });
                        ctx.closePath();
                        ctx.fill();
                        ctx.stroke();
                    }
                } else if (shape === 'text') {
                    var text = div.dataset.text || '';
                    var fontSize = parseFloat(div.dataset.fontSize) || 20;
                    var scale = parseFloat(div.dataset.scale) || 1;
                    ctx.font = (fontSize * scale) + 'px sans-serif';
                    ctx.fillText(text, left * w, top * h);
                }

                ctx.restore();
            });
        };

        if (img.complete && img.naturalWidth > 0) {
            draw();
        } else {
            img.addEventListener('load', draw);
        }

        // Toggle masks button (answer side)
        var toggleBtn = document.getElementById('toggle');
        if (toggleBtn) {
            toggleBtn.addEventListener('click', function () {
                canvas.style.display = canvas.style.display === 'none' ? 'block' : 'none';
            });
        }
    }
};
