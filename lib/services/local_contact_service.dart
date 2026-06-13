import 'dart:convert';

import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import '../models/contact.dart';

/// Service for reading/writing local system contacts via flutter_contacts.
class LocalContactService {
  /// Request contact permission. Returns true if granted.
  Future<bool> requestPermission() async {
    return await fc.FlutterContacts.requestPermission();
  }

  /// Check if contact permission is granted.
  Future<bool> hasPermission() async {
    // flutter_contacts doesn't have checkPermission, try requestPermission
    // or rely on getContacts returning empty on no permission
    return true;
  }

  /// Get all local contacts, mapped to our Contact model.
  Future<List<Contact>> getAllContacts() async {
    final fcContacts = await fc.FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
    );
    return fcContacts.map(_fromFlutterContact).toList();
  }

  /// Get a single contact by ID.
  Future<Contact?> getContact(String id) async {
    final fcContact = await fc.FlutterContacts.getContact(id);
    if (fcContact == null) return null;
    return _fromFlutterContact(fcContact);
  }

  /// Create a new local contact.
  Future<Contact> createContact(Contact contact) async {
    final fcContact = _toFlutterContact(contact);
    final created = await fc.FlutterContacts.insertContact(fcContact);
    return _fromFlutterContact(created);
  }

  /// Update an existing local contact.
  Future<Contact> updateContact(Contact contact) async {
    if (contact.uid == null) throw Exception('Contact UID (local ID) required for update');

    final existing = await fc.FlutterContacts.getContact(contact.uid!);
    if (existing == null) throw Exception('Local contact not found: ${contact.uid}');

    final updated = _mergeIntoFlutterContact(existing, contact);
    final saved = await fc.FlutterContacts.updateContact(updated);
    return _fromFlutterContact(saved);
  }

  /// Delete a local contact.
  Future<void> deleteContact(String id) async {
    final fcContact = await fc.FlutterContacts.getContact(id);
    if (fcContact != null) {
      await fc.FlutterContacts.deleteContact(fcContact);
    }
  }

  // ── Mappers ──

  Contact _fromFlutterContact(fc.Contact fcContact) {
    return Contact(
      uid: fcContact.id,
      displayName: fcContact.displayName,
      firstName: fcContact.name.first,
      lastName: fcContact.name.last,
      phones: fcContact.phones.map((p) => ContactPhone(
        number: p.number,
        label: _mapPhoneLabel(p.label),
      )).toList(),
      emails: fcContact.emails.map((e) => ContactEmail(
        address: e.address,
        label: _mapEmailLabel(e.label),
      )).toList(),
      organization: fcContact.organizations.isNotEmpty
          ? fcContact.organizations.first.company
          : null,
      title: fcContact.organizations.isNotEmpty
          ? fcContact.organizations.first.title
          : null,
      note: fcContact.notes.isNotEmpty ? fcContact.notes.first.note : null,
      addresses: fcContact.addresses.map((a) => ContactAddress(
        street: a.street,
        city: a.city,
        region: a.state,
        postalCode: a.postalCode,
        country: a.country,
        label: _mapAddressLabel(a.label),
      )).toList(),
      birthday: fcContact.events.isNotEmpty
          ? _parseBirthday(fcContact.events.first)
          : null,
      photo: fcContact.photo != null ? base64Encode(fcContact.photo!) : null,
    );
  }

  fc.Contact _toFlutterContact(Contact contact) {
    return fc.Contact(
      name: fc.Name(
        first: contact.firstName ?? '',
        last: contact.lastName ?? '',
      ),
      phones: contact.phones.map((p) => fc.Phone(
        p.number,
        label: _reversePhoneLabel(p.label),
      )).toList(),
      emails: contact.emails.map((e) => fc.Email(
        e.address,
        label: _reverseEmailLabel(e.label),
      )).toList(),
      organizations: contact.organization != null
          ? [fc.Organization(
              company: contact.organization ?? '',
              title: contact.title ?? '',
            )]
          : [],
      notes: contact.note != null ? [fc.Note(contact.note!)] : [],
      addresses: contact.addresses.map((a) => fc.Address(
        '${a.street ?? ''}',
        label: _reverseAddressLabel(a.label),
        street: a.street ?? '',
        city: a.city ?? '',
        state: a.region ?? '',
        postalCode: a.postalCode ?? '',
        country: a.country ?? '',
      )).toList(),
    );
  }

  fc.Contact _mergeIntoFlutterContact(fc.Contact existing, Contact contact) {
    existing.name.first = contact.firstName ?? '';
    existing.name.last = contact.lastName ?? '';
    existing.phones.clear();
    existing.phones.addAll(contact.phones.map((p) => fc.Phone(
      p.number,
      label: _reversePhoneLabel(p.label),
    )));
    existing.emails.clear();
    existing.emails.addAll(contact.emails.map((e) => fc.Email(
      e.address,
      label: _reverseEmailLabel(e.label),
    )));
    if (contact.organization != null) {
      if (existing.organizations.isEmpty) {
        existing.organizations.add(fc.Organization());
      }
      existing.organizations.first.company = contact.organization!;
      existing.organizations.first.title = contact.title ?? '';
    }
    existing.notes.clear();
    if (contact.note != null) existing.notes.add(fc.Note(contact.note!));
    return existing;
  }

  // ── Label mappers ──

  String _mapPhoneLabel(fc.PhoneLabel label) {
    switch (label) {
      case fc.PhoneLabel.mobile: return 'mobile';
      case fc.PhoneLabel.home: return 'home';
      case fc.PhoneLabel.work: return 'work';
      default: return 'other';
    }
  }

  fc.PhoneLabel _reversePhoneLabel(String label) {
    switch (label) {
      case 'mobile': return fc.PhoneLabel.mobile;
      case 'home': return fc.PhoneLabel.home;
      case 'work': return fc.PhoneLabel.work;
      default: return fc.PhoneLabel.other;
    }
  }

  String _mapEmailLabel(fc.EmailLabel label) {
    switch (label) {
      case fc.EmailLabel.home: return 'home';
      case fc.EmailLabel.work: return 'work';
      default: return 'other';
    }
  }

  fc.EmailLabel _reverseEmailLabel(String label) {
    switch (label) {
      case 'home': return fc.EmailLabel.home;
      case 'work': return fc.EmailLabel.work;
      default: return fc.EmailLabel.other;
    }
  }

  String _mapAddressLabel(fc.AddressLabel label) {
    switch (label) {
      case fc.AddressLabel.home: return 'home';
      case fc.AddressLabel.work: return 'work';
      default: return 'other';
    }
  }

  fc.AddressLabel _reverseAddressLabel(String label) {
    switch (label) {
      case 'home': return fc.AddressLabel.home;
      case 'work': return fc.AddressLabel.work;
      default: return fc.AddressLabel.other;
    }
  }

  DateTime? _parseBirthday(fc.Event event) {
    if (event.year == null) return null;
    return DateTime(event.year!, event.month, event.day);
  }
}
