document.addEventListener('DOMContentLoaded', () => {
    // Reveal animations on scroll
    const observerOptions = {
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('active');
            }
        });
    }, observerOptions);

    document.querySelectorAll('.reveal').forEach(el => observer.observe(el));

    // Modal Logic
    const modal = document.getElementById('modal');
    const openModalBtns = document.querySelectorAll('.open-modal, #nav-cta');
    const closeModalBtn = document.querySelector('.close-modal');
    const form = document.getElementById('early-access-form');
    const successMsg = document.getElementById('success-msg');

    const openModal = (e) => {
        if (e) e.preventDefault();
        modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    };

    const closeModal = () => {
        modal.style.display = 'none';
        document.body.style.overflow = 'auto';
    };

    openModalBtns.forEach(btn => btn.addEventListener('click', openModal));
    closeModalBtn.addEventListener('click', closeModal);

    window.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
    });

    // Form Submission Simulation
    form.addEventListener('submit', (e) => {
        e.preventDefault();
        
        // Disable button
        const btn = form.querySelector('button');
        const originalText = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Processing...';
        btn.disabled = true;

        // Simulate API call
        setTimeout(() => {
            form.style.display = 'none';
            successMsg.style.display = 'block';
            
            // Auto close after 3 seconds
            setTimeout(() => {
                closeModal();
                // Reset form for next time
                setTimeout(() => {
                    form.style.display = 'block';
                    successMsg.style.display = 'none';
                    btn.innerHTML = originalText;
                    btn.disabled = false;
                    form.reset();
                }, 500);
            }, 3000);
        }, 1500);
    });

    // Parallax effect for hero image
    window.addEventListener('scroll', () => {
        const scrolled = window.pageYOffset;
        const heroVisual = document.querySelector('.hero-visual');
        if (heroVisual) {
            heroVisual.style.transform = `translateY(${scrolled * 0.1}px) rotate(${scrolled * 0.02}deg)`;
        }
    });
});
