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
