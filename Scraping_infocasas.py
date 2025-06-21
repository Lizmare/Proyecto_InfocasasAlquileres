import time
import re
import pandas as pd
import requests
import undetected_chromedriver as uc
from selenium.webdriver.common.by import By
from selenium.common.exceptions import NoSuchElementException
from bs4 import BeautifulSoup as bs

# Inicializar navegador
options = uc.ChromeOptions()
driver = uc.Chrome(options=options)
url_base = "https://www.infocasas.com.bo"
driver.get(f"{url_base}/alquiler/departamentos/santa-cruz")
time.sleep(5)

data = []
enlaces_visitados = set()
pagina_actual = 1
max_paginas = 50

def extraer_links():
    soup = bs(driver.page_source, "lxml")
    links = []
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith("/lindo") or re.search(r'/[a-z0-9\-]+/\d+$', href):
            full_link = url_base + href
            if full_link not in enlaces_visitados:
                enlaces_visitados.add(full_link)
                links.append(full_link)
    return links

while pagina_actual <= max_paginas:
    print(f"\n Página {pagina_actual}")
    time.sleep(5)

    links = extraer_links()
    print(f"🔗 Enlaces únicos en esta página: {len(links)}")

    for idx, link in enumerate(links):
        try:
            driver.get(link)
            time.sleep(3)
            soup = bs(driver.page_source, 'lxml')

            titulo = soup.find('h1', class_='ant-typography property-title').get_text(strip=True)
            precio_span = soup.find('span', class_='ant-typography price')
            precio = precio_span.find('strong').text.strip() if precio_span else None
            spans = soup.find_all('span', class_='ant-typography ant-typography-ellipsis ant-typography-ellipsis-single-line')
            dormitorios = banios = area = None
            for span in spans:
                texto = span.get_text(strip=True).lower()
                if 'dorm' in texto:
                    dormitorios = re.search(r'\d+', texto).group() if re.search(r'\d+', texto) else None
                elif 'baño' in texto:
                    banios = re.search(r'\d+', texto).group() if re.search(r'\d+', texto) else None
                elif 'm²' in texto or 'm2' in texto:
                    area = re.search(r'\d+', texto).group() if re.search(r'\d+', texto) else None

            info_divs = soup.find_all('div', class_='ant-typography ant-typography-ellipsis ant-typography-ellipsis-multiple-line')
            info_values = [div.get('title') for div in info_divs]

            zona = info_values[2] if len(info_values) > 2 else None
            gastos_comunes = next((v for v in info_values if v and "U$S" in v), None)
            anio_construccion = next((v for v in info_values if v and v.isdigit() and len(v) == 4), None)

            descripcion_div = soup.find('div', class_='property-description')
            descripcion = descripcion_div.get_text(" ", strip=True).lower() if descripcion_div else ""
            garaje = "Garaje" if "garaje" in descripcion else None

            ubicacion_p = soup.find('p', style='margin: 0px;')
            ubicacion = ubicacion_p.get_text(strip=True) if ubicacion_p else None

            # Coordenadas
            response = requests.get(link, headers={"User-Agent": "Mozilla/5.0"})
            match = re.search(r'"latitude"\s*:\s*([-0-9.]+)\s*,\s*"longitude"\s*:\s*([-0-9.]+)', response.text)
            if not match:
                match = re.search(r'lat\s*[:=]\s*([-0-9.]+)\s*,\s*lng\s*[:=]\s*([-0-9.]+)', response.text)
            lat, lng = (match.group(1), match.group(2)) if match else (None, None)

            data.append({
                'titulo': titulo,
                'precio': precio,
                'dormitorios': dormitorios,
                'banios': banios,
                'zona': zona,
                'area': area,
                'gastos_comunes': gastos_comunes,
                'anio_construccion': anio_construccion,
                'garaje': garaje,
                'ubicacion': ubicacion,
                'latitud': lat,
                'longitud': lng,
                'url': link
            })

            print(f"   [{idx+1}/{len(links)}] {titulo}")

        except Exception as e:
            print(f"Error al procesar {link}: {e}")

        # Volver al listado
        driver.back()
        time.sleep(3)

    # Ir a siguiente página
    try:
        siguiente = driver.find_element(By.XPATH, "//a[normalize-space()='>']")
        driver.execute_script("arguments[0].scrollIntoView();", siguiente)
        siguiente.click()
        pagina_actual += 1
    except NoSuchElementException:
        print("No hay más páginas.")
        break
    except Exception as e:
        print(f"Error navegando a página {pagina_actual}: {e}")
        break

# Guardar datos
driver.quit()
df = pd.DataFrame(data).drop_duplicates(subset="url")
df.to_csv("infocasas_santa.csv", index=False, encoding="utf-8-sig")
print(f"\n Finalizado: {len(df)} propiedades guardadas.")

