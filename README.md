# Uatizapi 2 - Aplicativo Mobile de Chat em Tempo Real

## 📋 Informações do Projeto

**Disciplina:** Programação para Dispositivos Móveis  
**Professor:** Gustavo Meneghetti Arcolezi  
**Data de Entrega:** 18/11/2024  
**Versão:** 1.0.0  
**Status:** ✅ Completo

---

## 👥 Integrantes do Grupo

| Nome | RA |
|------|-----|
| Pedro Henrique Silva Olival | 170570-2024 |
| Renato Garcia Lopes | 171270-2024 |
| Gustavo de Lima Sossai | 173342-2024 |

---

## 📖 Sobre o Projeto

O **Uatizapi 2** é um aplicativo mobile desenvolvido em Flutter que permite comunicação em tempo real entre usuários através de conversas individuais ou em grupos. O projeto utiliza **Supabase** como backend, demonstrando o uso de serviços em nuvem modernos para sincronização em tempo real e boas práticas de desenvolvimento mobile.

### Objetivo

Desenvolver um aplicativo mobile em Flutter de chat em tempo real utilizando Supabase como backend. O app permite comunicação entre usuários em conversas individuais ou grupos, com mensagens instantâneas de texto e mídia simples.

---

## 🛠️ Tecnologias Utilizadas

### Frontend
- **Flutter** - Framework de desenvolvimento mobile multiplataforma
- **Dart** - Linguagem de programação

### Backend e Serviços
- **Supabase** - Backend as a Service (BaaS)
  - **Auth** - Autenticação por e-mail e senha
  - **PostgreSQL** - Banco de dados relacional
  - **Realtime** - Atualização instantânea de mensagens
  - **Storage** - Armazenamento de imagens e arquivos
  - **Edge Functions** - Automação de notificações
  - **RLS (Row Level Security)** - Segurança em nível de linha

### Dependências Principais
- `supabase_flutter: ^2.10.2` - Cliente Supabase para Flutter
- `firebase_core: ^3.5.0` - Firebase Core
- `firebase_messaging: ^15.0.3` - Notificações push
- `flutter_dotenv: ^6.0.0` - Gerenciamento de variáveis de ambiente
- `file_picker: ^8.1.4` - Seleção de arquivos
- `shared_preferences: ^2.3.3` - Armazenamento local

---

## ✨ Funcionalidades

### Autenticação
- ✅ Cadastro de usuários
- ✅ Login com e-mail e senha
- ✅ Recuperação de senha
- ✅ Controle de sessão

### Perfil
- ✅ Edição de nome e foto de perfil
- ✅ Visualização de perfil

### Conversas
- ✅ Conversas individuais (1 para 1)
- ✅ Conversas em grupo
- ✅ Grupos públicos (buscáveis) e privados
- ✅ Busca por usuários e grupos

### Mensagens
- ✅ Envio de mensagens de texto em tempo real
- ✅ Envio de imagens e arquivos (até 20 MB)
- ✅ Edição de mensagens (até 15 minutos após envio)
- ✅ Exclusão de mensagens pelo autor
- ✅ Reações a mensagens
- ✅ Indicador de "digitando..."
- ✅ Indicador de status online/offline

### Notificações
- ✅ Notificações push para novas mensagens

---

## 📁 Estrutura do Projeto

```
uatizapi2/
├── lib/
│   ├── main.dart                    # Ponto de entrada da aplicação
│   ├── firebase_options.dart        # Configurações do Firebase
│   ├── repositories/                # Implementações dos repositórios
│   │   ├── profile_repository.dart
│   │   ├── register_repository.dart
│   │   └── room_repository.dart
│   ├── services/                    # Serviços de negócio
│   │   ├── attachment_service.dart
│   │   ├── avatar_service.dart
│   │   ├── notification_service.dart
│   │   ├── password_recovery_service.dart
│   │   ├── profile_service.dart
│   │   ├── register_service.dart
│   │   └── room_service.dart
│   ├── ui/
│   │   ├── features/                # Telas da aplicação
│   │   │   ├── forgot_password/
│   │   │   ├── home/
│   │   │   ├── login/
│   │   │   └── register/
│   │   ├── theme/                   # Tema e cores
│   │   └── widgets/                 # Componentes reutilizáveis
│   └── utils/
│       └── routes_enum.dart        # Enum de rotas
├── assets/                          # Recursos estáticos
│   ├── icons/
│   ├── logos/
│   └── lottie/
├── android/                         # Configurações Android
├── ios/                             # Configurações iOS
└── pubspec.yaml                     # Dependências do projeto
```

---

## 🚀 Como Executar o Projeto

### Pré-requisitos

- Flutter SDK (versão 3.9.2 ou superior)
- Dart SDK
- Android Studio / Xcode (para desenvolvimento mobile)
- Conta no Supabase
- Conta no Firebase (para notificações push)

### Instalação

1. **Clone o repositório:**
```bash
git clone [url-do-repositório]
cd uatizapi2
```

2. **Instale as dependências:**
```bash
flutter pub get
```

3. **Configure as variáveis de ambiente:**
   
   Crie um arquivo `.env` na raiz do projeto com o seguinte conteúdo:
```env
SUPABASE_KEY=your_anon_key_here
SUPABASE_URL=your_supabase_url_here
```

4. **Configure o Firebase:**
   - Adicione os arquivos de configuração do Firebase:
     - `android/app/google-services.json` (Android)
     - `ios/Runner/GoogleService-Info.plist` (iOS)

5. **Execute o aplicativo:**
```bash
flutter run
```
---

## 🏗️ Arquitetura

### Backend (Supabase)

O projeto utiliza a seguinte estrutura no Supabase:

- **Auth**: Autenticação por e-mail e senha, com controle de sessão
- **Postgres**: Tabelas para usuários, conversas, participantes e mensagens
- **Realtime**: Atualização instantânea das mensagens e status dos usuários
- **Storage**: Upload e acesso a imagens e arquivos
- **Edge Functions**: Automação de notificações e manutenção de dados
- **RLS (Row Level Security)**: Segurança por usuário, garantindo acesso apenas aos próprios dados e conversas

### Regras de Negócio

- Qualquer usuário pode iniciar uma conversa com outro
- Grupos podem ser públicos (buscáveis) ou privados (acesso por convite/link)
- Mensagens podem ser editadas por até 15 minutos e apagadas pelo autor
- Tamanho máximo de arquivo: 20 MB
- Política de retenção de mensagens: 12 meses

---

## 📊 Requisitos Não Funcionais

- **Desempenho**: Mensagens entregues e exibidas em até 2 segundos
- **Segurança**: RLS e HTTPS obrigatórios, regras restritivas no Storage
- **Privacidade**: Opção de ocultar o status online e histórico local seguro
- **Acessibilidade**: Interface legível, contraste adequado e fontes escaláveis
- **Confiabilidade**: Funcionamento offline temporário com sincronização posterior

---

## ✅ Critérios de Aceitação

- ✅ Usuários autenticados trocam mensagens em tempo real
- ✅ Conversas e grupos funcionam com atualização instantânea
- ✅ Envio de texto e imagem ocorre sem erro e com confirmação visual
- ✅ Busca retorna resultados corretos
- ✅ Interface estável e intuitiva

---

## 📝 Entregáveis

- ✅ Código-fonte completo do app Flutter
- ✅ Banco de dados Supabase configurado e documentado
- ✅ Documento de arquitetura e regras RLS
- ✅ Relatório técnico explicando o funcionamento e o processo de desenvolvimento

---

## 🔒 Segurança

O projeto implementa segurança através de:

- **Row Level Security (RLS)**: Políticas de segurança no banco de dados que garantem que usuários só acessem seus próprios dados
- **HTTPS**: Todas as comunicações são criptografadas
- **Autenticação**: Sistema robusto de autenticação via Supabase Auth
- **Storage Rules**: Regras restritivas para acesso a arquivos no Storage

---

## 📚 Referências

- [Documentação Flutter](https://flutter.dev/docs)
- [Documentação Supabase](https://supabase.com/docs)
- [Documentação Firebase](https://firebase.google.com/docs)

---

## 📖 Documentação Adicional

Para mais detalhes sobre o projeto, consulte:

- **[DATABASE.md](./DATABASE.md)** - Documentação completa do banco de dados, incluindo estrutura de tabelas, funções RPC, Edge Functions, políticas RLS e scripts SQL
- **[DOCS.md](./DOCS.md)** - Documentação técnica do projeto

---

## 🐛 Troubleshooting

### Problemas Comuns

#### Erro ao conectar com Supabase
- Verifique se o arquivo `.env` está na raiz do projeto
- Confirme que as variáveis `SUPABASE_URL` e `SUPABASE_KEY` estão corretas
- Certifique-se de que o arquivo `.env` está incluído no `pubspec.yaml` (seção `assets`)

#### Erro ao executar no Android/iOS
- Execute `flutter clean` e depois `flutter pub get`
- Verifique se os arquivos de configuração do Firebase estão nos locais corretos:
  - Android: `android/app/google-services.json`
  - iOS: `ios/Runner/GoogleService-Info.plist`

#### Notificações push não funcionam
- Verifique se o Firebase está configurado corretamente
- Confirme que as permissões de notificação foram concedidas (especialmente no iOS)
- Verifique se o token FCM está sendo salvo na tabela `fcm_tokens`

#### Mensagens não aparecem em tempo real
- Verifique se o Realtime está habilitado no Supabase
- Confirme que as políticas RLS estão configuradas corretamente
- Verifique a conexão com a internet

---

## 📄 Licença

Este projeto foi desenvolvido como trabalho acadêmico para a disciplina de Programação para Dispositivos Móveis.

---

**Desenvolvido usando Flutter e Supabase**
