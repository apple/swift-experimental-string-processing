# python3 generateEmails.py > output.txt

import string
import random

domain_charset = string.ascii_letters + string.digits + ".-"
locale_charset = domain_charset + "_%+"

n = 1000

# for the most part this will generate mostly valid emails
# there are some edge cases with double hyphens and double periods that cause
# issues but otherwise this should work

for _ in range(n):
  domain_len = random.randint(2,64)
  locale_len = random.randint(2,64)
  tld_len = random.randint(2,10)
  
  domain = "".join(random.sample(domain_charset, domain_len))
  locale = "".join(random.sample(locale_charset, locale_len))
  tld = "".join(random.sample(string.ascii_lowercase, tld_len))
  email = locale + "@" + domain + "." + tld
  print(email.lower())
