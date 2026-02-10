// Shared JavaScript for Cloudflare R2 bucket index pages

document.addEventListener('DOMContentLoaded', function() {
    initializeCopyButtons();
    handleHashNavigation();
    initializeDetailsHashSync();
});

function initializeCopyButtons() {
    document.querySelectorAll('.code-block').forEach(block => {
        // Create copy button
        const copyBtn = document.createElement('button');
        copyBtn.textContent = 'Copy';
        copyBtn.className = 'copy-btn';
        copyBtn.addEventListener('click', function() {
            const code = block.querySelector('code');
            const text = code ? code.textContent : block.textContent;
            
            navigator.clipboard.writeText(text.trim()).then(() => {
                copyBtn.textContent = 'Copied!';
                setTimeout(() => {
                    copyBtn.textContent = 'Copy';
                }, 2000);
            }).catch(err => {
                console.error('Failed to copy text: ', err);
                // Fallback for older browsers
                fallbackCopyTextToClipboard(text.trim(), copyBtn);
            });
        });
        
        block.style.position = 'relative';
        block.appendChild(copyBtn);
    });
}

function handleHashNavigation() {
    var hash = window.location.hash.substring(1);
    if (!hash) return;

    var target = document.getElementById(hash);
    if (!target) return;

    // Close all details elements, then open only the target
    document.querySelectorAll('details').forEach(function(d) {
        d.removeAttribute('open');
    });

    if (target.tagName === 'DETAILS') {
        target.setAttribute('open', '');
    }

    // Scroll to the target after a short delay to let the DOM settle
    setTimeout(function() {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 100);

    // Add a brief highlight
    target.classList.add('anchor-highlight');
    setTimeout(function() {
        target.classList.remove('anchor-highlight');
    }, 2000);
}

function initializeDetailsHashSync() {
    document.querySelectorAll('details[id]').forEach(function(details) {
        details.addEventListener('toggle', function() {
            if (details.open) {
                history.replaceState(null, '', '#' + details.id);
            } else if (window.location.hash === '#' + details.id) {
                history.replaceState(null, '', window.location.pathname + window.location.search);
            }
        });
    });
}

function fallbackCopyTextToClipboard(text, button) {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-999999px';
    textArea.style.top = '-999999px';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    
    try {
        document.execCommand('copy');
        button.textContent = 'Copied!';
        setTimeout(() => {
            button.textContent = 'Copy';
        }, 2000);
    } catch (err) {
        console.error('Fallback copy failed: ', err);
        button.textContent = 'Failed';
        setTimeout(() => {
            button.textContent = 'Copy';
        }, 2000);
    }
    
    document.body.removeChild(textArea);
}

 