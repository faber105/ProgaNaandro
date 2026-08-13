import 'react-native-url-polyfill/auto';

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { StatusBar } from 'expo-status-bar';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';
const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { storage: AsyncStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
});

type Message = {
  id: string;
  user_id: string;
  nickname: string;
  body: string;
  created_at: string;
};

const NICK_KEY = 'anonymous-chat-nickname';

export default function App() {
  const [nickname, setNickname] = useState('');
  const [draftNick, setDraftNick] = useState('');
  const [messages, setMessages] = useState<Message[]>([]);
  const [text, setText] = useState('');
  const [userId, setUserId] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const listRef = useRef<FlatList<Message>>(null);

  const configured = Boolean(supabaseUrl && supabaseAnonKey);

  useEffect(() => {
    void boot();
  }, []);

  async function boot() {
    if (!configured) {
      setError('Сервер ещё не настроен. Добавьте ключи Supabase в .env.');
      setLoading(false);
      return;
    }

    const savedNick = await AsyncStorage.getItem(NICK_KEY);
    if (savedNick) setNickname(savedNick);

    const { data: sessionData } = await supabase.auth.getSession();
    let id = sessionData.session?.user.id;
    if (!id) {
      const { data, error: authError } = await supabase.auth.signInAnonymously();
      if (authError) {
        setError('Не удалось войти анонимно. Проверьте настройки Supabase.');
        setLoading(false);
        return;
      }
      id = data.user?.id;
    }
    if (id) setUserId(id);

    const { data, error: loadError } = await supabase
      .from('messages')
      .select('*')
      .order('created_at', { ascending: true })
      .limit(200);

    if (loadError) setError('Не удалось загрузить сообщения.');
    else setMessages((data as Message[]) ?? []);

    supabase
      .channel('public-chat')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, (payload) => {
        const next = payload.new as Message;
        setMessages((current) => current.some((item) => item.id === next.id) ? current : [...current, next]);
      })
      .subscribe();

    setLoading(false);
  }

  async function saveNickname() {
    const clean = draftNick.trim().replace(/\s+/g, ' ').slice(0, 24);
    if (clean.length < 2) {
      setError('Ник должен быть минимум из 2 символов.');
      return;
    }
    await AsyncStorage.setItem(NICK_KEY, clean);
    setNickname(clean);
    setError('');
  }

  async function send() {
    const body = text.trim().slice(0, 1000);
    if (!body || !nickname || !userId || sending) return;
    setSending(true);
    setText('');
    const { error: sendError } = await supabase.from('messages').insert({
      user_id: userId,
      nickname,
      body,
    });
    if (sendError) {
      setText(body);
      setError('Сообщение не отправилось. Попробуйте ещё раз.');
    } else {
      setError('');
    }
    setSending(false);
  }

  const header = useMemo(() => (
    <View style={styles.header}>
      <View>
        <Text style={styles.eyebrow}>ОБЩАЯ КОМНАТА</Text>
        <Text style={styles.title}>Тихий чат</Text>
      </View>
      <View style={styles.online}><View style={styles.dot} /><Text style={styles.onlineText}>онлайн</Text></View>
    </View>
  ), []);

  if (loading) {
    return <SafeAreaView style={styles.center}><ActivityIndicator color="#5A43C6" /><Text style={styles.muted}>Подключаемся…</Text></SafeAreaView>;
  }

  if (!nickname) {
    return (
      <SafeAreaView style={styles.onboarding}>
        <StatusBar style="dark" />
        <Text style={styles.mark}>ТЧ</Text>
        <View style={styles.intro}>
          <Text style={styles.eyebrow}>БЕЗ ПРОФИЛЯ. БЕЗ ЛИШНЕГО.</Text>
          <Text style={styles.hero}>Выберите ник и заходите.</Text>
          <Text style={styles.description}>Другие увидят только ваш ник. Не используйте настоящее имя, если хотите остаться анонимным.</Text>
        </View>
        <View style={styles.nickArea}>
          <TextInput
            value={draftNick}
            onChangeText={setDraftNick}
            placeholder="Например, ЛунныйКот"
            placeholderTextColor="#8E8A99"
            maxLength={24}
            autoCapitalize="none"
            style={styles.nickInput}
            onSubmitEditing={saveNickname}
          />
          {!!error && <Text style={styles.error}>{error}</Text>}
          <Pressable style={({ pressed }) => [styles.primary, pressed && styles.pressed]} onPress={saveNickname}>
            <Text style={styles.primaryText}>Войти в чат</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.page}>
      <StatusBar style="dark" />
      {header}
      <FlatList
        ref={listRef}
        data={messages}
        keyExtractor={(item) => item.id}
        contentContainerStyle={messages.length ? styles.list : styles.emptyList}
        onContentSizeChange={() => listRef.current?.scrollToEnd({ animated: true })}
        ListEmptyComponent={<View><Text style={styles.emptyTitle}>Здесь пока тихо.</Text><Text style={styles.muted}>Напишите первое сообщение.</Text></View>}
        renderItem={({ item }) => {
          const mine = item.user_id === userId;
          return (
            <View style={[styles.messageRow, mine && styles.messageRowMine]}>
              <Text style={styles.author}>{mine ? 'вы' : item.nickname}</Text>
              <View style={[styles.bubble, mine && styles.bubbleMine]}>
                <Text style={[styles.body, mine && styles.bodyMine]}>{item.body}</Text>
              </View>
            </View>
          );
        }}
      />
      {!!error && <Text style={styles.chatError}>{error}</Text>}
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={styles.composer}>
          <TextInput
            value={text}
            onChangeText={setText}
            placeholder={`Сообщение от ${nickname}`}
            placeholderTextColor="#8E8A99"
            multiline
            maxLength={1000}
            style={styles.composerInput}
          />
          <Pressable
            accessibilityLabel="Отправить сообщение"
            disabled={!text.trim() || sending}
            onPress={send}
            style={({ pressed }) => [styles.send, (!text.trim() || sending) && styles.sendDisabled, pressed && styles.pressed]}
          >
            <Text style={styles.sendText}>↑</Text>
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, backgroundColor: '#F4F2EB' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, backgroundColor: '#F4F2EB' },
  onboarding: { flex: 1, paddingHorizontal: 24, paddingVertical: 32, justifyContent: 'space-between', backgroundColor: '#F4F2EB' },
  mark: { width: 52, height: 52, paddingTop: 14, textAlign: 'center', overflow: 'hidden', borderRadius: 18, backgroundColor: '#1D1A22', color: '#F4F2EB', fontSize: 16, fontWeight: '800' },
  intro: { gap: 16 },
  eyebrow: { color: '#5A43C6', fontSize: 12, lineHeight: 16, fontWeight: '800', letterSpacing: 1.2 },
  hero: { color: '#1D1A22', fontSize: 44, lineHeight: 48, fontWeight: '800', letterSpacing: -1.4 },
  description: { color: '#625E69', fontSize: 17, lineHeight: 26, maxWidth: 520 },
  nickArea: { gap: 12 },
  nickInput: { minHeight: 56, borderWidth: 1, borderColor: '#D6D1C7', borderRadius: 18, paddingHorizontal: 18, backgroundColor: '#FAF8F2', color: '#1D1A22', fontSize: 17 },
  primary: { minHeight: 56, borderRadius: 18, alignItems: 'center', justifyContent: 'center', backgroundColor: '#5A43C6' },
  primaryText: { color: '#F9F7FF', fontSize: 16, fontWeight: '800' },
  pressed: { opacity: 0.78, transform: [{ scale: 0.985 }] },
  error: { color: '#A23747', fontSize: 14, lineHeight: 20 },
  header: { minHeight: 88, paddingHorizontal: 20, paddingVertical: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: 1, borderBottomColor: '#DDD8CD' },
  title: { color: '#1D1A22', fontSize: 24, lineHeight: 30, fontWeight: '800', letterSpacing: -0.5 },
  online: { flexDirection: 'row', gap: 7, alignItems: 'center' },
  dot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#2F936F' },
  onlineText: { color: '#625E69', fontSize: 13, fontWeight: '600' },
  list: { paddingHorizontal: 16, paddingVertical: 24, gap: 18 },
  emptyList: { flexGrow: 1, alignItems: 'center', justifyContent: 'center' },
  emptyTitle: { color: '#1D1A22', fontSize: 24, lineHeight: 30, fontWeight: '800', marginBottom: 4 },
  muted: { color: '#797480', fontSize: 15, lineHeight: 22 },
  messageRow: { maxWidth: '84%', alignSelf: 'flex-start', gap: 5 },
  messageRowMine: { alignSelf: 'flex-end', alignItems: 'flex-end' },
  author: { color: '#797480', fontSize: 12, lineHeight: 16, fontWeight: '700', paddingHorizontal: 6 },
  bubble: { borderRadius: 20, borderBottomLeftRadius: 6, backgroundColor: '#E7E2D8', paddingHorizontal: 15, paddingVertical: 11 },
  bubbleMine: { borderBottomLeftRadius: 20, borderBottomRightRadius: 6, backgroundColor: '#5A43C6' },
  body: { color: '#252129', fontSize: 16, lineHeight: 23 },
  bodyMine: { color: '#F9F7FF' },
  chatError: { color: '#A23747', fontSize: 13, lineHeight: 18, paddingHorizontal: 18, paddingVertical: 6 },
  composer: { flexDirection: 'row', alignItems: 'flex-end', gap: 10, padding: 12, borderTopWidth: 1, borderTopColor: '#DDD8CD', backgroundColor: '#F4F2EB' },
  composerInput: { flex: 1, maxHeight: 120, minHeight: 48, borderRadius: 18, backgroundColor: '#FAF8F2', borderWidth: 1, borderColor: '#D6D1C7', paddingHorizontal: 16, paddingVertical: 12, color: '#1D1A22', fontSize: 16, lineHeight: 22 },
  send: { width: 48, height: 48, borderRadius: 18, alignItems: 'center', justifyContent: 'center', backgroundColor: '#5A43C6' },
  sendDisabled: { backgroundColor: '#C7C1D3' },
  sendText: { color: '#F9F7FF', fontSize: 27, lineHeight: 30, fontWeight: '500' },
});
