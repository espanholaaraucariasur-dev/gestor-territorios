import os
import re

directory = r'c:\Users\Angel Rivas\araucaria_sur\lib'

for root, dirs, files in os.walk(directory):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = re.sub(r'\(([\w\.]+)\.data\(\)\?\)', r'(\1.data() as Map<String, dynamic>?)', content)
            
            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f'Fixed {filepath}')
