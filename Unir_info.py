import pandas as pd
df_cbba= pd.read_csv('infocasas_cochabamba.csv')
df_cbba['ciudad'] = 'Cochabamba'

df_lpz = pd.read_csv('infocasas_lapaz.csv', skiprows=1, names=df_cbba.columns)
df_lpz['ciudad'] = 'La Paz'

df_sc = pd.read_csv('infocasas_santacruz.csv', skiprows=1, names=df_cbba.columns)
df_sc['ciudad'] = 'Santa Cruz'

df_total = pd.concat([df_cbba, df_lpz, df_sc], ignore_index=True)
df_total.to_csv('infocasas_bol.csv', index=False)
print("CSV general'ciudades_unidas.csv'")

df = pd.read_csv('infocasas_bol.csv')

duplicados = df.duplicated(subset=['titulo', 'url', 'latitud', 'longitud'], keep=False)
print(f"Total duplicados: {duplicados.sum()}")
