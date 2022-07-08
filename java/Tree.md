---
title: Tree
tags: 数据结构与算法
categories: Java基础
data: 2020-09-19 14:44:04
---
# Tree

## 定义

```java
public static class Node {
    int value;
    Node left;
    Node right;
}
```

## 二叉树前序遍历

```java
public static void printDLR(Node root) {
        if (root == null) {
            return;
        }
        System.out.println(root.value);
        printDLR(root.left);
        printDLR(root.right);
    }
```

## 二叉树中序遍历

```java
public static void printLDR(Node root) {
        if (root == null) {
            return;
        }
        printLDR(root.left);
        System.out.println(root.value);
        printLDR(root.right);
    }
```

## 二叉树后序遍历

```java
public static void printLRD(Node root) {
        if (root == null) {
            return;
        }
        printLRD(root.left);
        printLRD(root.right);
        System.out.println(root.value);
    }
```

## 二叉树层级遍历

```java
public static void printLevel0(Node root) {
        ArrayDeque<Node> queue = new ArrayDeque<>();
        queue.add(root);
        while (queue.size() != 0) {
            Node node = queue.poll();
            System.out.println(node.value);
            if (node.left != null) {
                queue.add(node.left);
            }
            if (node.right != null) {
                queue.add(node.right);
            }
        }
    }


public static List<List<Integer>> printLevel1(Node root) {
        List<List<Integer>> allLevelList = new ArrayList<>();
        ArrayDeque<Node> queue = new ArrayDeque<>();
        queue.add(root);
        while (queue.size() != 0) {
            int size = queue.size();
            List<Integer> levelList = new ArrayList<>();
            for (int index = 0; index < size; index++) {
                Node node = queue.poll();
                levelList.add(node.value);
                if (node.left != null) {
                    queue.add(node.left);
                }
                if (node.right != null) {
                    queue.add(node.right);
                }
            }
            allLevelList.add(levelList);
        }
        return allLevelList;
    }


public static List<List<Integer>> printLevel2(Node root) {
        List<List<Integer>> list = new ArrayList<>();
        if (root == null) {
            return list;
        }
        Queue<Node> queue = new LinkedList<>();
        queue.add(root);
        while (true) {
            List<Integer> list1 = new ArrayList<>();
            int size = queue.size();
            if (size == 0) {
                return list;
            }
            for (int i = 0; i < size; i++) {
                Node t = queue.poll();
                list1.add(t.value);
                if (t.left != null) {
                    queue.add(t.left);
                }
                if (t.right != null) {
                    queue.add(t.right);
                }
            }
            list.add(list1);
        }
    }
```

## 二叉树右视图

**右视图其实就是层级遍历之后取每个层级的最右节点的值**

```java
public static void printRightView(Node root) {
        List<List<Integer>> allLevelList = printLevel1(root);
        for (List<Integer> levelList : allLevelList) {
            System.out.println(levelList.get(levelList.size() - 1));
        }
    }
```

## 二叉树左视图

**左视图其实就是层级遍历之后取每个层级的最左节点的值**

```java
public static void printLeftView(Node root) {
        List<List<Integer>> allLevelList = printLevel1(root);
        for (List<Integer> levelList : allLevelList) {
            System.out.println(levelList.get(0));
        }
    }
```

