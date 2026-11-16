import { memo, useCallback, useLayoutEffect, useRef, useState, useSyncExternalStore } from 'react';
import { FlatList, KeyboardAvoidingView, Platform, Pressable, ScrollView, StatusBar, StyleSheet,
  Text, View, useColorScheme, type ListRenderItemInfo } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import type { ActionEvent } from '@openuidev/react-lang';
import { library, NativeContentProvider, NativeThemeProvider, useOpenUITheme } from './src/library';
import { samples, type GallerySample } from './src/demo/samples';
import { replayMessage } from './src/demo/replay';
import { OpenUIDocument } from './src/runtime/OpenUIDocument';
import { createMessageController, type MessageController } from './src/runtime/message';

type ThemeMode = 'system' | 'light' | 'dark';
type GalleryMessage = Readonly<{ id: string; sample: GallerySample; message: MessageController }>;
type MessageActions = { onReplay: (record: GalleryMessage) => void; onStop: (record: GalleryMessage) => void };
const modes: readonly { value: ThemeMode; label: string }[] = [
  { value: 'system', label: '系统' }, { value: 'light', label: '浅色' }, { value: 'dark', label: '深色' },
];
const resolveImage = (source: string) => source === 'asset://west-lake'
  ? require('../Gallery/Resources/Images/west-lake.jpg') as number : undefined;

function makeMessage(id: number, sample: GallerySample): GalleryMessage {
  const message = createMessageController(`gallery-${id}`);
  message.complete(message.begin(sample.source));
  return { id: message.messageId, sample, message };
}

function Control({ title, onPress, selected, disabled = false, label }: {
  title: string; onPress: () => void; selected?: boolean; disabled?: boolean; label?: string;
}) {
  const theme = useOpenUITheme();
  return <Pressable accessibilityRole="button" accessibilityLabel={label ?? title}
    accessibilityState={{ selected, disabled }} disabled={disabled} onPress={onPress}
    style={({ pressed }) => [styles.control, {
      minHeight: theme.controlMinHeight, borderColor: selected ? theme.accent : theme.border,
      backgroundColor: selected ? theme.accent : pressed ? theme.surfaceMuted : theme.surface,
      opacity: disabled ? 0.45 : pressed ? 0.8 : 1,
    }]}>
    <Text style={[styles.controlText, { color: selected ? theme.onAccent : theme.ink }]}>{title}</Text>
  </Pressable>;
}

function MessageStatus({ message }: { message: MessageController }) {
  const theme = useOpenUITheme();
  const snapshot = useSyncExternalStore(message.subscribe, message.getSnapshot, message.getSnapshot);
  const labels = { streaming: '正在生成', complete: '已完成 · 可以交互', interrupted: '已停止 · 预览已冻结', error: '内容已暂停' };
  return <Text accessibilityLiveRegion="polite" style={[styles.caption, { color: theme.muted }]}>
    {labels[snapshot.phase]}{snapshot.phase === 'error' ? ` · ${message.getError()?.message}` : ''}
  </Text>;
}

function SourcePreview({ message }: { message: MessageController }) {
  const theme = useOpenUITheme();
  const snapshot = useSyncExternalStore(message.subscribe, message.getSnapshot, message.getSnapshot);
  return <View style={[styles.source, { backgroundColor: theme.code }]}>
    <Text style={[styles.caption, { color: theme.muted }]}>当前接收的原始 Lang · {snapshot.source.length} UTF-16 单元</Text>
    <ScrollView style={styles.sourceScroll} nestedScrollEnabled keyboardShouldPersistTaps="handled">
      <Text selectable style={[styles.code, { color: theme.ink }]}>{snapshot.source || '等待内容…'}</Text>
    </ScrollView>
  </View>;
}

function Diagnostics({ message, error }: { message: MessageController; error: string }) {
  const theme = useOpenUITheme();
  const snapshot = useSyncExternalStore(message.subscribe, message.getSnapshot, message.getSnapshot);
  return error && (snapshot.phase === 'complete' || snapshot.phase === 'error')
    ? <Text accessibilityRole="alert" style={[styles.caption, { color: theme.destructive }]}>{error}</Text> : null;
}

function MessageContent({ message, visible }: { message: MessageController; visible: boolean }) {
  const theme = useOpenUITheme();
  const [error, setError] = useState('');
  const [events, setEvents] = useState<string[]>([]);
  const onAction = useCallback((event: ActionEvent) => {
    setEvents(previous => [JSON.stringify(event, null, 2), ...previous].slice(0, 3));
  }, []);
  const onPersistenceError = useCallback((reason: Error) => setError(reason.message), []);
  const onError = useCallback((errors: { message: string }[]) => setError(errors.map(item => item.message).join('\n')), []);
  return <>
    {visible ? <OpenUIDocument message={message} library={library} onAction={onAction}
      onError={onError} onPersistenceError={onPersistenceError} />
      : <View style={[styles.hidden, { backgroundColor: theme.surfaceMuted }]}>
        <Text style={[styles.body, { color: theme.muted }]}>消息视图已卸载。恢复后会读取宿主保存的字段。</Text>
      </View>}
    <Diagnostics message={message} error={error} />
    {events.length > 0 && <View style={[styles.eventLog, { borderColor: theme.border }]}>
      <Text style={[styles.caption, { color: theme.muted }]}>宿主事件 · 仅在本地记录，最近 3 条</Text>
      {events.map((event, index) => <Text key={`${index}:${event}`} selectable
        style={[styles.code, { color: theme.ink }]}>{event}</Text>)}
    </View>}
  </>;
}

const MessageRow = memo(function MessageRow({ record, ordinal, onReplay, onStop }:
  { record: GalleryMessage; ordinal: number } & MessageActions) {
  const theme = useOpenUITheme();
  const [visible, setVisible] = useState(true);
  const [showSource, setShowSource] = useState(false);
  // Only a new epoch rerenders this row. Source updates stay inside subscribed leaves.
  const handle = useSyncExternalStore(record.message.subscribe, record.message.getHandle, record.message.getHandle);
  return <View style={[styles.message, { borderColor: theme.border }]}>
    <View style={styles.messageHeading}>
      <Text style={[styles.eyebrow, { color: theme.accent }]}>{String(ordinal).padStart(2, '0')} / {record.sample.title}</Text>
      <MessageStatus message={record.message} />
    </View>
    <MessageContent key={handle.epoch} message={record.message} visible={visible} />
    <View style={styles.controls}>
      <Control title="流式回放" label={`流式回放${record.sample.title}`} onPress={() => { setVisible(true); onReplay(record); }} />
      <Control title="停止" label={`停止${record.sample.title}`} onPress={() => onStop(record)} />
      <Control title={visible ? '卸载消息' : '恢复消息'} onPress={() => setVisible(value => !value)} />
      <Control title={showSource ? '收起源码' : '查看源码'} onPress={() => setShowSource(value => !value)} />
    </View>
    {showSource && <SourcePreview message={record.message} />}
  </View>;
});

function Gallery({ mode, setMode }: { mode: ThemeMode; setMode: (mode: ThemeMode) => void }) {
  const theme = useOpenUITheme();
  const systemScheme = useColorScheme();
  const [records, setRecords] = useState<GalleryMessage[]>(() => [makeMessage(1, samples[0])]);
  const recordsRef = useRef(records);
  const serial = useRef(1);
  const lifecycle = useRef(0);
  const mounted = useRef(true);
  const replays = useRef(new Map<string, () => void>());
  const list = useRef<FlatList<GalleryMessage>>(null);

  const release = useCallback((record: GalleryMessage) => {
    replays.current.get(record.id)?.(); replays.current.delete(record.id);
    record.message.dispose();
  }, []);
  useLayoutEffect(() => {
    mounted.current = true;
    const generation = ++lifecycle.current;
    return () => {
      mounted.current = false;
      // React's development effect replay must not dispose the still-mounted host.
      queueMicrotask(() => {
        if (lifecycle.current === generation) recordsRef.current.forEach(release);
      });
    };
  }, [release]);
  const onReplay = useCallback((record: GalleryMessage) => {
    if (!mounted.current || !recordsRef.current.includes(record)) return;
    replays.current.get(record.id)?.();
    replays.current.set(record.id, replayMessage(record.message, record.sample.source));
  }, []);
  const onStop = useCallback((record: GalleryMessage) => {
    if (!mounted.current || !recordsRef.current.includes(record)) return;
    replays.current.get(record.id)?.(); replays.current.delete(record.id);
    record.message.interrupt(record.message.getHandle());
  }, []);
  const append = (sample: GallerySample) => {
    if (!mounted.current) return;
    // New samples appear first, so navigation never depends on estimating the
    // height of an unmeasured long message or a later image layout callback.
    const next = [makeMessage(++serial.current, sample), ...recordsRef.current];
    const evicted = next.length > 8 ? next.pop() : undefined;
    recordsRef.current = next; setRecords(next);
    if (evicted) release(evicted);
    list.current?.scrollToOffset({ offset: 0, animated: true });
  };
  const clearHistory = () => {
    if (!mounted.current) return;
    const current = recordsRef.current;
    recordsRef.current = current.slice(0, 1); setRecords(recordsRef.current);
    current.slice(1).forEach(release);
  };
  const renderItem = useCallback(({ item, index }: ListRenderItemInfo<GalleryMessage>) =>
    <MessageRow record={item} ordinal={index + 1} onReplay={onReplay} onStop={onStop} />, [onReplay, onStop]);

  return <SafeAreaView style={[styles.page, { backgroundColor: theme.background }]}>
    <StatusBar barStyle={(mode === 'system' ? systemScheme : mode) === 'dark' ? 'light-content' : 'dark-content'} />
    <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <FlatList ref={list} data={records} keyExtractor={record => record.id} renderItem={renderItem}
        initialNumToRender={2} maxToRenderPerBatch={2} windowSize={5} removeClippedSubviews={false}
        keyboardShouldPersistTaps="handled" keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
        contentContainerStyle={styles.content}
        ListHeaderComponent={<View style={styles.header}>
          <View style={styles.topline}>
            <Text style={[styles.eyebrow, { color: theme.accent }]}>OPENUI / NATIVE GALLERY</Text>
            <Text style={[styles.caption, { color: theme.muted }]}>离线样例</Text>
          </View>
          <Text accessibilityRole="header" style={[styles.title, { color: theme.ink }]}>让界面，{'\n'}跟着内容生长。</Text>
          <Text style={[styles.body, { color: theme.muted }]}>同一份契约，原生的内容与交互。选择样例添加消息，检查流式过程与输入恢复。</Text>
          <View style={styles.controls}>{samples.map(sample =>
            <Control key={sample.id} title={`＋ ${sample.label}`} label={`添加${sample.label}样例`} onPress={() => append(sample)} />)}</View>
          <View style={styles.themeControls} accessibilityLabel="外观">
            {modes.map(item => <Control key={item.value} title={item.label} label={`${item.label}主题`}
              selected={mode === item.value} onPress={() => setMode(item.value)} />)}
          </View>
          <View style={styles.topline}>
            <Text style={[styles.caption, styles.shrink, { color: theme.muted }]}>最新消息在上方 · 最多 8 条</Text>
            <Control title="清空历史" disabled={records.length < 2} onPress={clearHistory} />
          </View>
        </View>}
        ListFooterComponent={<Text style={[styles.footer, { color: theme.muted }]}>消息视图可以离开屏幕，字段由宿主保存。回放会开始新的生成，并清空该消息的旧字段。</Text>} />
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

export default function App() {
  const [mode, setMode] = useState<ThemeMode>('system');
  return <SafeAreaProvider><NativeThemeProvider colorScheme={mode}>
    <NativeContentProvider resolveImage={resolveImage}><Gallery mode={mode} setMode={setMode} /></NativeContentProvider>
  </NativeThemeProvider></SafeAreaProvider>;
}

const styles = StyleSheet.create({
  flex: { flex: 1 }, shrink: { flexShrink: 1 }, page: { flex: 1 },
  content: { paddingHorizontal: 22, paddingBottom: 32, maxWidth: 760, width: '100%', alignSelf: 'center' },
  header: { gap: 18, paddingTop: 24, paddingBottom: 32 },
  topline: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, alignItems: 'center', justifyContent: 'space-between' },
  eyebrow: { fontSize: 11, letterSpacing: 1.2, lineHeight: 18, fontWeight: '600', flexShrink: 1 },
  title: { fontSize: 36, lineHeight: 47, fontWeight: '600', letterSpacing: -0.8 },
  body: { fontSize: 15, lineHeight: 24 }, caption: { fontSize: 12, lineHeight: 19 },
  controls: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  themeControls: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  control: { justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderRadius: 12, paddingHorizontal: 15, paddingVertical: 10 },
  controlText: { fontSize: 13, lineHeight: 19, fontWeight: '500' },
  message: { borderTopWidth: 1, paddingTop: 24, paddingBottom: 32, gap: 22 },
  messageHeading: { gap: 4 }, hidden: { padding: 20, borderRadius: 12 },
  source: { borderRadius: 12, padding: 14, gap: 10 }, sourceScroll: { maxHeight: 240 },
  code: { fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace', fontSize: 12, lineHeight: 19 },
  eventLog: { borderLeftWidth: 2, paddingLeft: 14, gap: 10 },
  footer: { paddingVertical: 12, fontSize: 12, lineHeight: 20 },
});
