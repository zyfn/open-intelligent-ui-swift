import { useMemo, useState } from 'react';
import { FlatList, Modal, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useOpenUITheme } from '../library/theme';
import { componentSamples } from './componentSamples';
import { samples, type GallerySample } from './samples';
import { contentSamples, cardSamples } from './contentSamples';
import { formSamples } from './formSamples';
import { dataSamples } from './dataSamples';

const scenarios = [...samples, ...contentSamples, ...cardSamples, ...formSamples, ...dataSamples];
const categories = ['全部', ...new Set(componentSamples.map(sample => sample.category))];

export function ComponentBrowser({ visible, onClose, onSelect }: {
  visible: boolean; onClose: () => void; onSelect: (sample: GallerySample) => void;
}) {
  const theme = useOpenUITheme();
  const [section, setSection] = useState<'components' | 'scenarios'>('components');
  const [category, setCategory] = useState('全部');
  const [search, setSearch] = useState('');
  const items = useMemo(() => (section === 'components' ? componentSamples : scenarios)
    .filter(sample => (section === 'scenarios' || category === '全部' || ('category' in sample && sample.category === category))
      && `${sample.label} ${sample.title}`.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase())), [section, category, search]);
  return <Modal visible={visible} animationType="slide" onRequestClose={onClose} accessibilityViewIsModal>
    {visible ? <SafeAreaView style={{ flex: 1, paddingHorizontal: 20, backgroundColor: theme.background }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16, paddingVertical: 8 }}>
        <Text accessibilityRole="header" style={{ flex: 1, color: theme.ink, fontSize: 24, fontWeight: '600' }}>OpenUI</Text>
        <Pressable accessibilityRole="button" accessibilityLabel="关闭组件目录" onPress={onClose}
          style={{ minHeight: 48, minWidth: 48, justifyContent: 'center', alignItems: 'center' }}>
          <Text style={{ color: theme.accent, fontSize: 16 }}>完成</Text>
        </Pressable>
      </View>
      <View style={{ flexDirection: 'row', gap: 20 }}>
        {([{ value: 'components', label: `组件 · ${componentSamples.length}` },
          { value: 'scenarios', label: '组合场景' }] as const).map(item =>
          <Pressable key={item.value} accessibilityRole="tab" accessibilityState={{ selected: section === item.value }}
            onPress={() => setSection(item.value)} style={{ minHeight: 48, justifyContent: 'center',
              borderBottomWidth: 2, borderBottomColor: section === item.value ? theme.accent : 'transparent' }}>
            <Text style={{ color: section === item.value ? theme.accent : theme.muted, fontSize: 16 }}>{item.label}</Text>
          </Pressable>)}
      </View>
      <TextInput accessibilityLabel="搜索OpenUI组件" value={search} onChangeText={setSearch}
        placeholder={section === 'components' ? '搜索组件' : '搜索场景'} placeholderTextColor={theme.muted}
        autoCapitalize="none" autoCorrect={false} clearButtonMode="while-editing"
        style={{ minHeight: 48, paddingHorizontal: 14, borderWidth: 1, borderColor: theme.border,
          borderRadius: 12, color: theme.ink, backgroundColor: theme.surface, marginVertical: 14, fontSize: 15 }} />
      {section === 'components' ? <View style={{ marginBottom: 12 }}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }} keyboardShouldPersistTaps="handled">
          {categories.map(name => <Pressable key={name} accessibilityRole="button" accessibilityLabel={`${name}组件`}
            accessibilityState={{ selected: category === name }} onPress={() => setCategory(name)}
            style={{ minHeight: 44, paddingHorizontal: 12, justifyContent: 'center', borderRadius: 10,
              backgroundColor: category === name ? theme.accent : theme.surface }}>
            <Text style={{ color: category === name ? theme.onAccent : theme.ink, fontSize: 13 }}>{name}</Text>
          </Pressable>)}
        </ScrollView>
      </View> : null}
      <FlatList data={items} keyExtractor={sample => sample.id} keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag" initialNumToRender={12} maxToRenderPerBatch={12}
        ListEmptyComponent={<Text style={{ color: theme.muted, paddingVertical: 24 }}>没有匹配的内容</Text>}
        renderItem={({ item }) => <Pressable accessibilityRole="button" accessibilityLabel={`打开${item.title}样例`}
          onPress={() => { onSelect(item); onClose(); }} style={({ pressed }) => ({ minHeight: 64,
            justifyContent: 'center', gap: 4, borderBottomWidth: 1, borderBottomColor: theme.border,
            opacity: pressed ? 0.65 : 1, paddingVertical: 12 })}>
          <Text style={{ color: theme.ink, fontSize: 16, fontWeight: '500' }}>{item.title}</Text>
          {'category' in item ? <Text style={{ color: theme.muted, fontSize: 12 }}>{String(item.category)}</Text> : null}
        </Pressable>} />
    </SafeAreaView> : null}
  </Modal>;
}
