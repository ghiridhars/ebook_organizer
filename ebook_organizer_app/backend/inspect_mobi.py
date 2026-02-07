
try:
    import mobi
    print("Mobi package found.")
    print(f"Dir: {dir(mobi)}")
    try:
        from mobi import Mobi
        print("Successfully imported Mobi class.")
    except ImportError as e:
        print(f"Failed to import Mobi class: {e}")
except ImportError:
    print("Mobi package not found.")
