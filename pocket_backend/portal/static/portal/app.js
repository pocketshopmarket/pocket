document.addEventListener('DOMContentLoaded', () => {
    // ─── Reveal Animations on Scroll ───
    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry, index) => {
            if (entry.isIntersecting) {
                // Stagger the animation slightly for grid children
                const delay = entry.target.dataset.delay || 0;
                setTimeout(() => {
                    entry.target.classList.add('active');
                }, delay);
            }
        });
    }, { threshold: 0.1 });

    document.querySelectorAll('.reveal').forEach((el, i) => {
        // Add stagger delays to grid items
        if (el.closest('.features-grid') || el.closest('.persona-container') || el.closest('.steps')) {
            const siblings = el.parentElement.querySelectorAll('.reveal');
            const idx = Array.from(siblings).indexOf(el);
            el.dataset.delay = idx * 100;
        }
        observer.observe(el);
    });

    // ─── Sticky Header Shadow ───
    const header = document.getElementById('site-header');
    window.addEventListener('scroll', () => {
        if (window.scrollY > 10) {
            header.classList.add('scrolled');
        } else {
            header.classList.remove('scrolled');
        }
    });

    // ─── Smooth Scroll for Anchor Links ───
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', (e) => {
            const targetId = anchor.getAttribute('href');
            if (targetId === '#') return;
            e.preventDefault();
            const target = document.querySelector(targetId);
            if (target) {
                const offset = header.offsetHeight + 20;
                const top = target.getBoundingClientRect().top + window.pageYOffset - offset;
                window.scrollTo({ top, behavior: 'smooth' });
            }
            // Close mobile nav if open
            navLinks.classList.remove('open');
            mobileToggle.querySelector('i').className = 'fas fa-bars';
        });
    });

    // ─── Mobile Navigation Toggle ───
    const mobileToggle = document.getElementById('mobile-toggle');
    const navLinks = document.getElementById('nav-links');

    mobileToggle.addEventListener('click', () => {
        navLinks.classList.toggle('open');
        const icon = mobileToggle.querySelector('i');
        icon.className = navLinks.classList.contains('open') ? 'fas fa-xmark' : 'fas fa-bars';
    });

    // ─── Modal Logic ───
    const modal = document.getElementById('modal');
    const openModalBtns = document.querySelectorAll('.open-modal');
    const closeModalBtn = document.getElementById('close-modal');
    const form = document.getElementById('early-access-form');
    const successMsg = document.getElementById('success-msg');

    const openModal = (e) => {
        if (e) e.preventDefault();
        modal.classList.add('visible');
        document.body.style.overflow = 'hidden';
    };

    const closeModal = () => {
        modal.classList.remove('visible');
        document.body.style.overflow = 'auto';
    };

    openModalBtns.forEach(btn => btn.addEventListener('click', openModal));
    closeModalBtn.addEventListener('click', closeModal);

    window.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
    });

    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeModal();
    });

    // ─── Form Submission ───
    form.addEventListener('submit', (e) => {
        e.preventDefault();

        const btn = form.querySelector('button[type="submit"]');
        const originalText = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Processing...';
        btn.disabled = true;

        setTimeout(() => {
            form.style.display = 'none';
            successMsg.style.display = 'block';

            setTimeout(() => {
                closeModal();
                setTimeout(() => {
                    form.style.display = 'block';
                    successMsg.style.display = 'none';
                    btn.innerHTML = originalText;
                    btn.disabled = false;
                    form.reset();
                }, 400);
            }, 2500);
        }, 1200);
    });
    // ─── Hero Slideshow ───
    const slides = document.querySelectorAll('.slide');
    const dots = document.querySelectorAll('.dot');
    let currentSlide = 0;
    let slideInterval;

    function goToSlide(index) {
        slides[currentSlide].classList.remove('active');
        dots[currentSlide].classList.remove('active');
        currentSlide = index;
        slides[currentSlide].classList.add('active');
        dots[currentSlide].classList.add('active');
    }

    function nextSlide() {
        goToSlide((currentSlide + 1) % slides.length);
    }

    function startSlideshow() {
        slideInterval = setInterval(nextSlide, 3500);
    }

    // Dot click navigation
    dots.forEach(dot => {
        dot.addEventListener('click', () => {
            clearInterval(slideInterval);
            goToSlide(parseInt(dot.dataset.index));
            startSlideshow();
        });
    });

    if (slides.length > 0) {
        startSlideshow();
    }
});
