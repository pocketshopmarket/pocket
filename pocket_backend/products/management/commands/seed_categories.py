import os
from django.core.management.base import BaseCommand
from django.utils.text import slugify
from products.models import Category

class Command(BaseCommand):
    help = 'Seeds the database with core categories and subcategories'

    def handle(self, *args, **kwargs):
        categories_data = {
            'Electronics': {
                'icon': 'devices',
                'subcategories': [
                    'Smartphones & Accessories', 'Laptops & Computers', 'TVs & Home Entertainment',
                    'Audio (Headphones, Speakers)', 'Gaming (Consoles, Accessories)', 'Cameras & Photography',
                    'Smart Devices (IoT, Wearables)'
                ]
            },
            'Fashion': {
                'icon': 'checkroom',
                'subcategories': [
                    'Men’s Clothing', 'Women’s Clothing', 'Kids’ Clothing', 'Shoes', 'Bags & Accessories', 'Jewelry & Watches'
                ]
            },
            'Home & Living': {
                'icon': 'chair',
                'subcategories': [
                    'Furniture', 'Home Decor', 'Kitchen & Dining', 'Bedding & Bath', 'Lighting', 'Storage & Organization'
                ]
            },
            'Beauty & Personal Care': {
                'icon': 'face_retouching_natural',
                'subcategories': [
                    'Skincare', 'Haircare', 'Makeup', 'Fragrances', 'Grooming (Men/Women)'
                ]
            },
            'Health & Wellness': {
                'icon': 'health_and_safety',
                'subcategories': [
                    'Vitamins & Supplements', 'Medical Supplies', 'Fitness Equipment', 'Personal Care Devices'
                ]
            },
            'Groceries & Food': {
                'icon': 'local_grocery_store',
                'subcategories': [
                    'Fresh Produce', 'Packaged Foods', 'Beverages', 'Snacks', 'Household Essentials'
                ]
            },
            'Baby & Kids': {
                'icon': 'child_care',
                'subcategories': [
                    'Baby Clothing', 'Diapers & Wipes', 'Toys', 'Baby Gear (Strollers, Car Seats)'
                ]
            },
            'Sports & Outdoors': {
                'icon': 'sports_basketball',
                'subcategories': [
                    'Fitness Gear', 'Outdoor Equipment', 'Sportswear', 'Camping & Hiking'
                ]
            },
            'Automotive': {
                'icon': 'directions_car',
                'subcategories': [
                    'Car Accessories', 'Spare Parts', 'Tools & Equipment', 'Motorbike Accessories'
                ]
            },
            'Books & Media': {
                'icon': 'menu_book',
                'subcategories': [
                    'Books', 'E-books', 'Music', 'Movies'
                ]
            },
            'Office & Stationery': {
                'icon': 'edit',
                'subcategories': [
                    'Office Supplies', 'School Supplies', 'Printers & Accessories'
                ]
            },
            'Tools & Home Improvement': {
                'icon': 'build',
                'subcategories': [
                    'Power Tools', 'Hand Tools', 'Building Materials', 'Electrical & Plumbing'
                ]
            },
            'Pet Supplies': {
                'icon': 'pets',
                'subcategories': [
                    'Pet Food', 'Accessories', 'Grooming Products'
                ]
            },
            'Digital Products': {
                'icon': 'cloud_download',
                'subcategories': [
                    'Software', 'Online Courses', 'Subscriptions'
                ]
            }
        }

        self.stdout.write('Clearing existing categories...')
        Category.objects.all().delete()

        self.stdout.write('Seeding categories...')
        for parent_name, data in categories_data.items():
            parent_cat, created = Category.objects.get_or_create(
                name=parent_name,
                slug=slugify(parent_name),
                defaults={'icon_name': data['icon']}
            )
            
            for sub_name in data['subcategories']:
                Category.objects.get_or_create(
                    name=sub_name,
                    slug=slugify(sub_name),
                    parent=parent_cat,
                    defaults={'icon_name': None}
                )

        self.stdout.write(self.style.SUCCESS(f'Successfully seeded {len(categories_data)} parent categories!'))
