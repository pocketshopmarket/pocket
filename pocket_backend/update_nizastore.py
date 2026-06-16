from accounts.models import SellerProfile

profile = SellerProfile.objects.filter(shop_name__iexact='nizastore').first()
if not profile:
    print("ERROR: nizastore not found")
else:
    profile.shop_location = 'Jambo Drive, Kitwe, Copperbelt Province, Zambia'
    profile.shop_lat = -12.80556
    profile.shop_lng = 28.24028
    profile.save()
    print(f"Updated: {profile.shop_name} → {profile.shop_location}")
