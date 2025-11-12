# Projeto de Aplicativo Mobile de Chat em

# Tempo Real (Flutter + Supabase)

### _________________________________________________________________________

## Disciplina: Programação para Dispositivos Móveis

Professor: Gustavo Meneghetti Arcolezi
_________________________________________________________________________

## 1) Objetivo

Desenvolver um **aplicativo mobile em Flutter** de chat em tempo real utilizando **Supabase**
como backend. O app permite comunicação entre usuários em conversas individuais ou
grupos, com mensagens instantâneas de texto e mídia simples.
O projeto busca demonstrar o uso de serviços em nuvem modernos para sincronização em
tempo real e boas práticas de desenvolvimento mobile com Flutter.

## 2) Escopo

```
● Plataforma obrigatória: Mobile (Flutter).
● Backend: Supabase (Auth, Realtime, Postgres, Storage).
● Funcionalidades principais:
○ Cadastro e login de usuários.
○ Perfil com nome e imagem.
○ Conversas individuais e em grupo.
○ Envio de mensagens em tempo real (texto, imagem, arquivo leve).
○ Indicador de online e digitando.
○ Busca por usuários e grupos.
○ Reações a mensagens.
```
## 3) Arquitetura (Supabase)

```
● Auth : autenticação por e-mail e senha, com controle de sessão.
● Postgres : tabelas para usuários, conversas, participantes e mensagens.
● Realtime : atualização instantânea das mensagens e status dos usuários.
● Storage : upload e acesso a imagens e arquivos.
● Edge Functions : automação de notificações e manutenção de dados.
● RLS (Row Level Security) : segurança por usuário, garantindo acesso apenas aos
```
## próprios dados e conversas.


## 4) Regras de Negócio

```
● Qualquer usuário pode iniciar uma conversa com outro.
● Grupos podem ser públicos (buscáveis) ou privados (acesso por convite/link).
● Mensagens podem ser editadas por até 15 minutos e apagadas pelo autor.
● Tamanho máximo de arquivo: 20 MB.
● Política de retenção de mensagens: 12 meses.
```
## 5) Requisitos Não Funcionais

```
● Desempenho : mensagens entregues e exibidas em até 2 segundos.
● Segurança : RLS e HTTPS obrigatórios, regras restritivas no Storage.
● Privacidade : opção de ocultar o status online e histórico local seguro.
● Acessibilidade : interface legível, contraste adequado e fontes escaláveis.
● Confiabilidade : funcionamento offline temporário com sincronização posterior.
```
## 6) Critérios de Aceitação

```
● Usuários autenticados trocam mensagens em tempo real.
● Conversas e grupos funcionam com atualização instantânea.
● Envio de texto e imagem ocorre sem erro e com confirmação visual.
● Busca retorna resultados corretos.
● Interface estável e intuitiva.
```
## 7) Entregáveis

```
● Código-fonte completo do app Flutter.
● Banco de dados Supabase configurado e documentado.
● Documento de arquitetura e regras RLS.
● Relatório técnico explicando o funcionamento e o processo de desenvolvimento.
```
## 8) Cronograma (6 semanas)

● **Semanas 1–2:** Configuração do Supabase e autenticação no app.
● **Semanas 3–4:** Implementação das conversas e envio de mensagens.
● **Semana 5:** Funcionalidades adicionais (busca, reações, presença).
● **Semana 6:** Testes, ajustes finais e entrega.
**Data de entrega e apresentação: 25/11/**

## 9) Riscos e Mitigações

```
● Latência alta: otimizar consultas e uso do Realtime.
● Armazenamento excessivo: limitar tamanho e tempo de retenção de mídia.
```

● **Falhas de autenticação:** revisar regras de segurança e testar fluxos de login/logout.
● **Perda de conexão:** garantir reenvio automático de mensagens quando reconectar.


## 10) Ajustes Recentes

```
● Tabela rooms: adicionar coluna is_searchable boolean default false.
● RPC create_group_room: aceitar parâmetro is_searchable e persistir na coluna.
● Grupos marcados como pesquisáveis aparecem em buscas públicas (feature em desenvolvimento).
```

### Scripts SQL

```sql
alter table public.rooms
  add column if not exists is_searchable boolean not null default false;
```



