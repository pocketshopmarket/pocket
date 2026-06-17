from django.shortcuts import render

def index(request):
    return render(request, 'portal/index.html')

def terms(request):
    return render(request, 'portal/terms.html')

def privacy(request):
    return render(request, 'portal/privacy.html')
