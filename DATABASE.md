# Documentação do Banco de Dados - Uatizapi 2

## 📋 Visão Geral

Este documento descreve a estrutura completa do banco de dados do projeto **Uatizapi2**, desenvolvido utilizando **Supabase** (PostgreSQL). O banco de dados foi projetado para suportar um sistema de chat em tempo real com conversas individuais e em grupo.

---

## 🗄️ Estrutura do Banco de Dados

### Schema: `public`

O banco de dados utiliza o schema padrão `public` do PostgreSQL, com todas as tabelas acessíveis através da API do Supabase.

---

## 📊 Tabelas

### 0. `auth.users` (Supabase Auth)

Tabela gerenciada automaticamente pelo Supabase Auth para autenticação de usuários.

#### Estrutura (Campos Principais)

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | `uuid` | PRIMARY KEY, Identificador único do usuário |
| `email` | `text` | E-mail do usuário (único) |
| `encrypted_password` | `text` | Senha criptografada |
| `email_confirmed_at` | `timestamp` | Data de confirmação do e-mail |
| `created_at` | `timestamp` | Data de criação da conta |
| `updated_at` | `timestamp` | Data da última atualização |
| `user_metadata` | `jsonb` | Metadados do usuário (ex: `full_name`) |

#### Relacionamentos

- **1:1** com `profiles` (via `id`)
- Esta tabela é gerenciada exclusivamente pelo Supabase Auth

#### Observações

- A tabela `auth.users` é do schema `auth` e não `public`
- Não deve ser acessada diretamente via API, apenas através do Supabase Auth
- O campo `user_metadata` pode armazenar informações como `full_name` que são usadas no app

---

### 1. `profiles`

Armazena informações adicionais dos perfis de usuários, complementando a tabela `auth.users` do Supabase Auth.

#### Estrutura

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `id` | `uuid` | PRIMARY KEY, FK → `auth.users.id` | Identificador único do usuário (mesmo ID do auth.users) |
| `email` | `text` | NOT NULL, UNIQUE | E-mail do usuário |
| `avatar_url` | `text` | NULLABLE | URL da imagem de perfil do usuário (armazenada no Supabase Storage) |
| `created_at` | `timestamp` | DEFAULT `now()` | Data de criação do perfil |
| `updated_at` | `timestamp` | DEFAULT `now()` | Data da última atualização |

#### Relacionamentos

- **1:1** com `auth.users` (via `id`)
- **1:N** com `room_members` (um usuário pode estar em múltiplas salas)
- **1:N** com `messages` (um usuário pode enviar múltiplas mensagens)

#### Políticas RLS (Row Level Security)

- Usuários podem ler seus próprios perfis
- Usuários podem atualizar seus próprios perfis
- Usuários podem ler perfis de outros usuários (para busca e exibição)

---

### 2. `rooms`

Armazena as salas de conversa, que podem ser do tipo **direta** (1 para 1) ou **grupo** (múltiplos participantes).

#### Estrutura

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `id` | `uuid` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Identificador único da sala |
| `name` | `text` | NOT NULL | Nome da sala (para grupos) ou nome derivado (para diretas) |
| `type` | `text` | NOT NULL, CHECK (`type` IN ('direct', 'group')) | Tipo da sala: 'direct' ou 'group' |
| `is_searchable` | `boolean` | NOT NULL, DEFAULT `false` | Indica se o grupo pode ser encontrado em buscas públicas |
| `created_at` | `timestamp` | DEFAULT `now()` | Data de criação da sala |
| `updated_at` | `timestamp` | DEFAULT `now()` | Data da última atualização (atualizada quando há nova mensagem) |

#### Relacionamentos

- **1:N** com `room_members` (uma sala tem múltiplos membros)
- **1:N** com `messages` (uma sala contém múltiplas mensagens)

#### Políticas RLS (Row Level Security)

- Usuários só podem ler salas das quais são membros
- Apenas funções RPC podem criar salas
- Usuários podem atualizar apenas salas de grupo das quais são membros

#### Observações

- Salas do tipo `direct` são criadas automaticamente pela função RPC `create_direct_room`
- Salas do tipo `group` são criadas pela função RPC `create_group_room`
- O campo `updated_at` é atualizado automaticamente quando novas mensagens são inseridas

---

### 3. `room_members`

Tabela de relacionamento muitos-para-muitos entre usuários e salas, representando a participação de usuários em conversas.

#### Estrutura

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `room_id` | `uuid` | PRIMARY KEY, FK → `rooms.id` | Identificador da sala |
| `user_id` | `uuid` | PRIMARY KEY, FK → `profiles.id` | Identificador do usuário |
| `joined_at` | `timestamp` | DEFAULT `now()` | Data em que o usuário entrou na sala |
| `last_read_at` | `timestamp` | NULLABLE | Data da última mensagem lida pelo usuário (para indicadores de não lidas) |

#### Chave Primária Composta

A chave primária é composta por `(room_id, user_id)`, garantindo que um usuário não possa estar duplicado na mesma sala.

#### Relacionamentos

- **N:1** com `rooms` (múltiplos membros por sala)
- **N:1** com `profiles` (um usuário pode estar em múltiplas salas)

#### Políticas RLS (Row Level Security)

- Usuários só podem ler membros de salas das quais fazem parte
- Usuários podem inserir-se em grupos públicos (`is_searchable = true`)
- Apenas funções RPC podem adicionar membros a salas diretas

---

### 4. `messages`

Armazena todas as mensagens enviadas nas salas de conversa.

#### Estrutura

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `id` | `uuid` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Identificador único da mensagem |
| `room_id` | `uuid` | NOT NULL, FK → `rooms.id` | Sala à qual a mensagem pertence |
| `from_id` | `uuid` | NOT NULL, FK → `profiles.id` | Usuário que enviou a mensagem |
| `from_name` | `text` | NOT NULL | Nome do remetente (cache para performance) |
| `content` | `text` | NOT NULL | Conteúdo da mensagem (texto ou URL de anexo) |
| `parent_id` | `uuid` | NULLABLE, FK → `messages.id` | ID da mensagem respondida (para threads) |
| `created_at` | `timestamp` | DEFAULT `now()` | Data de criação da mensagem |
| `edited_at` | `timestamp` | NULLABLE | Data da última edição (NULL se nunca foi editada) |

#### Relacionamentos

- **N:1** com `rooms` (múltiplas mensagens por sala)
- **N:1** com `profiles` (múltiplas mensagens por usuário)
- **N:1** com `messages` (auto-relacionamento para respostas)

#### Políticas RLS (Row Level Security)

- Usuários só podem ler mensagens de salas das quais são membros
- Usuários só podem inserir mensagens em salas das quais são membros
- Usuários só podem atualizar suas próprias mensagens
- Usuários só podem deletar suas próprias mensagens
- Mensagens só podem ser editadas até 15 minutos após a criação (validação via RLS)

#### Observações

- O campo `content` pode conter:
  - Texto simples para mensagens de texto
  - URL pública para mensagens com anexos (imagens, arquivos)
- O campo `from_name` é um cache do nome do usuário para evitar joins desnecessários
- O campo `parent_id` permite criar threads de conversa (respostas a mensagens)

---

### 5. `message_reactions`

Armazena as reações (emojis) dos usuários às mensagens.

#### Estrutura

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `id` | `uuid` | PRIMARY KEY, DEFAULT `gen_random_uuid()` | Identificador único da reação |
| `room_id` | `uuid` | NOT NULL, FK → `rooms.id` | Sala da mensagem (para filtragem eficiente) |
| `message_id` | `uuid` | NOT NULL, FK → `messages.id` | Mensagem à qual a reação pertence |
| `user_id` | `uuid` | NOT NULL, FK → `profiles.id` | Usuário que reagiu |
| `reaction` | `text` | NOT NULL | Emoji da reação (ex: '👍', '❤️', '😂') |
| `created_at` | `timestamp` | DEFAULT `now()` | Data da reação |

#### Relacionamentos

- **N:1** com `rooms` (múltiplas reações por sala)
- **N:1** com `messages` (múltiplas reações por mensagem)
- **N:1** com `profiles` (múltiplas reações por usuário)

#### Políticas RLS (Row Level Security)

- Usuários só podem ler reações de salas das quais são membros
- Usuários só podem inserir reações em mensagens de salas das quais são membros
- Usuários podem remover suas próprias reações
- Um usuário pode ter apenas uma reação por mensagem (validação via constraint ou aplicação)

---

### 6. `fcm_tokens`

Armazena os tokens FCM (Firebase Cloud Messaging) dos dispositivos dos usuários para envio de notificações push.

#### Estrutura

| Coluna | Tipo | Restrições | Descrição |
|--------|------|------------|-----------|
| `user_id` | `uuid` | PRIMARY KEY, FK → `profiles.id` | Identificador do usuário |
| `token` | `text` | NOT NULL, UNIQUE | Token FCM do dispositivo |
| `platform` | `text` | NOT NULL | Plataforma do dispositivo ('android', 'ios', 'web', etc.) |
| `updated_at` | `timestamp` | DEFAULT `now()` | Data da última atualização do token |

#### Relacionamentos

- **1:1** com `profiles` (um usuário pode ter um token por dispositivo)

#### Políticas RLS (Row Level Security)

- Usuários só podem ler e atualizar seus próprios tokens
- Usuários podem inserir seus próprios tokens

#### Observações

- A tabela utiliza `upsert` para atualizar tokens existentes ou inserir novos
- Tokens são atualizados quando o usuário faz login ou quando o token expira

---

## 🔧 Funções RPC (Remote Procedure Calls)

### 1. `create_direct_room`

Cria ou retorna uma sala de conversa direta entre dois usuários.

#### Parâmetros

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `target_user_id` | `uuid` | ID do usuário com quem se deseja conversar |

#### Retorno

- `text` (UUID da sala): Retorna o `id` da sala direta criada ou existente

#### Funcionalidade

1. Verifica se já existe uma sala direta entre os dois usuários
2. Se existir, retorna o ID da sala existente
3. Se não existir, cria uma nova sala do tipo `direct`
4. Adiciona ambos os usuários como membros da sala
5. Retorna o ID da sala

#### Políticas de Segurança

- Apenas usuários autenticados podem chamar esta função
- O usuário não pode criar uma sala direta consigo mesmo

---

### 2. `create_group_room`

Cria uma nova sala de grupo com múltiplos membros.

#### Parâmetros

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `group_name` | `text` | Nome do grupo |
| `member_ids` | `uuid[]` | Array com os IDs dos membros do grupo |
| `is_searchable` | `boolean` | Indica se o grupo pode ser encontrado em buscas públicas |

#### Retorno

- `text` (UUID da sala): Retorna o `id` da sala de grupo criada

#### Funcionalidade

1. Valida que o nome do grupo não está vazio
2. Valida que há pelo menos um membro além do criador
3. Cria uma nova sala do tipo `group`
4. Adiciona todos os membros especificados (incluindo o criador) à tabela `room_members`
5. Retorna o ID da sala criada

#### Políticas de Segurança

- Apenas usuários autenticados podem chamar esta função
- O criador é automaticamente adicionado como membro

---

## 🔧 Edge Functions

Além das funções RPC, o projeto utiliza **Supabase Edge Functions** para processamento serverless.

### 1. `send-notification`

Edge Function responsável por enviar notificações push quando novas mensagens são criadas.

#### Parâmetros de Entrada

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `room_id` | `string` (UUID) | ID da sala onde a mensagem foi enviada |
| `from_user_id` | `string` (UUID) | ID do usuário que enviou a mensagem |
| `message_preview` | `string` | Preview do conteúdo da mensagem (texto ou indicador de anexo) |

#### Funcionalidade

1. Busca todos os membros da sala (exceto o remetente)
2. Obtém os tokens FCM de cada membro da tabela `fcm_tokens`
3. Envia notificação push via Firebase Cloud Messaging para cada token
4. A notificação inclui:
   - Título: Nome do remetente ou nome da sala
   - Corpo: Preview da mensagem
   - Dados: `room_id` para navegação direta

#### Observações

- A função é chamada de forma assíncrona após o envio da mensagem
- Falhas na função não impedem o envio da mensagem
- A função pode ser implementada em Deno/TypeScript ou Node.js

---

## 🔐 Row Level Security (RLS)

Todas as tabelas do banco de dados possuem **Row Level Security** habilitado, garantindo que:

1. **Isolamento de Dados**: Usuários só podem acessar dados relacionados a eles
2. **Segurança em Nível de Banco**: As políticas são aplicadas diretamente no PostgreSQL
3. **Prevenção de Acesso Não Autorizado**: Mesmo que a aplicação tenha falhas, o banco protege os dados

### Políticas Principais

#### `profiles`
- **SELECT**: Usuários podem ler todos os perfis (para busca)
- **UPDATE**: Usuários só podem atualizar seus próprios perfis

#### `rooms`
- **SELECT**: Usuários só podem ler salas das quais são membros
- **INSERT**: Apenas via funções RPC
- **UPDATE**: Apenas para salas de grupo das quais são membros

#### `room_members`
- **SELECT**: Usuários só podem ler membros de salas das quais fazem parte
- **INSERT**: 
  - Via RPC para salas diretas
  - Diretamente para grupos públicos (`is_searchable = true`)

#### `messages`
- **SELECT**: Usuários só podem ler mensagens de salas das quais são membros
- **INSERT**: Usuários só podem inserir mensagens em salas das quais são membros
- **UPDATE**: Usuários só podem atualizar suas próprias mensagens, e apenas até 15 minutos após a criação
- **DELETE**: Usuários só podem deletar suas próprias mensagens

#### `message_reactions`
- **SELECT**: Usuários só podem ler reações de salas das quais são membros
- **INSERT**: Usuários só podem inserir reações em mensagens de salas das quais são membros
- **DELETE**: Usuários só podem remover suas próprias reações

#### `fcm_tokens`
- **SELECT**: Usuários só podem ler seus próprios tokens
- **INSERT/UPDATE**: Usuários só podem gerenciar seus próprios tokens

---

## 📦 Supabase Storage

Além das tabelas do banco de dados, o projeto utiliza o **Supabase Storage** para armazenar arquivos.

### Buckets

#### `avatars`
- **Propósito**: Armazenar imagens de perfil dos usuários
- **Políticas**:
  - Leitura pública (qualquer um pode ver avatares)
  - Escrita apenas pelo próprio usuário
- **Estrutura de Pastas**: `{user_id}/avatar.{ext}`

#### `attachments`
- **Propósito**: Armazenar anexos enviados nas mensagens (imagens, arquivos)
- **Políticas**:
  - Leitura apenas para membros da sala
  - Escrita apenas para membros da sala
- **Estrutura de Pastas**: `{room_id}/{message_id}/{filename}`
- **Limite de Tamanho**: 20 MB por arquivo

---

## 🔄 Realtime Subscriptions

O projeto utiliza o **Supabase Realtime** para atualizações em tempo real. As seguintes tabelas possuem subscriptions habilitadas:

1. **`messages`**: Atualizações em tempo real quando novas mensagens são enviadas
2. **`message_reactions`**: Atualizações em tempo real quando reações são adicionadas/removidas
3. **`room_members`**: Atualizações quando usuários entram/saem de salas
4. **`rooms`**: Atualizações quando informações da sala são modificadas

### Configuração

As subscriptions são configuradas no código Flutter usando:

```dart
Supabase.instance.client
  .from('messages')
  .stream(primaryKey: ['id'])
  .eq('room_id', roomId)
  .order('created_at', ascending: true);
```

---

## 📈 Índices Recomendados

Para otimizar as consultas, os seguintes índices são recomendados (e devem estar criados no banco):

1. **`rooms`**:
   - Índice em `type` (para filtrar salas diretas vs grupos)
   - Índice em `is_searchable` (para busca de grupos públicos)
   - Índice em `updated_at` (para ordenar conversas por última mensagem)

2. **`room_members`**:
   - Índice composto em `(user_id, room_id)` (para buscar salas de um usuário)
   - Índice em `room_id` (para buscar membros de uma sala)

3. **`messages`**:
   - Índice em `room_id` (para buscar mensagens de uma sala)
   - Índice em `created_at` (para ordenação)
   - Índice em `from_id` (para buscar mensagens de um usuário)

4. **`message_reactions`**:
   - Índice composto em `(message_id, user_id)` (para verificar reações existentes)
   - Índice em `room_id` (para filtrar reações por sala)

---

## 🔍 Consultas Comuns

### Buscar salas de um usuário

```sql
SELECT r.*
FROM rooms r
INNER JOIN room_members rm ON r.id = rm.room_id
WHERE rm.user_id = :user_id
ORDER BY r.updated_at DESC;
```

### Buscar mensagens de uma sala

```sql
SELECT *
FROM messages
WHERE room_id = :room_id
ORDER BY created_at ASC;
```

### Buscar grupos públicos

```sql
SELECT *
FROM rooms
WHERE type = 'group' 
  AND is_searchable = true
ORDER BY updated_at DESC;
```

### Contar mensagens não lidas

```sql
SELECT COUNT(*)
FROM messages m
INNER JOIN room_members rm ON m.room_id = rm.room_id
WHERE rm.user_id = :user_id
  AND m.room_id = :room_id
  AND m.created_at > COALESCE(rm.last_read_at, '1970-01-01'::timestamp)
  AND m.from_id != :user_id;
```

---

## 🛠️ Scripts SQL de Manutenção

### Adicionar coluna `is_searchable` à tabela `rooms`

```sql
ALTER TABLE public.rooms
  ADD COLUMN IF NOT EXISTS is_searchable BOOLEAN NOT NULL DEFAULT false;
```

### Criar índice para busca de grupos públicos

```sql
CREATE INDEX IF NOT EXISTS idx_rooms_searchable 
ON public.rooms(type, is_searchable, updated_at DESC)
WHERE type = 'group' AND is_searchable = true;
```

### Limpar mensagens antigas (política de retenção de 12 meses)

```sql
DELETE FROM public.messages
WHERE created_at < NOW() - INTERVAL '12 months';
```

---

## 📝 Notas de Implementação

1. **Timestamps**: Todas as tabelas utilizam `timestamp with time zone` para armazenar datas, garantindo consistência entre diferentes fusos horários.

2. **UUIDs**: Todos os identificadores utilizam UUID v4, gerados automaticamente pelo PostgreSQL através de `gen_random_uuid()`.

3. **Soft Deletes**: Atualmente, as mensagens são deletadas permanentemente. Para implementar soft deletes, seria necessário adicionar uma coluna `deleted_at`.

4. **Cascata**: As foreign keys não possuem `ON DELETE CASCADE` para evitar exclusões acidentais. As exclusões devem ser feitas manualmente pela aplicação.

5. **Triggers**: O campo `updated_at` da tabela `rooms` pode ser atualizado automaticamente via trigger quando novas mensagens são inseridas.

---

## 🔗 Referências

- [Documentação Supabase](https://supabase.com/docs)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Row Level Security Guide](https://supabase.com/docs/guides/auth/row-level-security)

---

**Última atualização**: Novembro 2024  
**Versão do Banco de Dados**: 1.0

